import Foundation
import Testing
@testable import NabtoWebRTC
@testable import NabtoWebRTCUtil

/// A signaling client that sends nowhere. The test hands the transport
/// incoming messages at chosen moments through `deliver`.
private actor FakeSignalingClient: SignalingClient {
    private struct WeakObserver {
        weak var value: SignalingClientObserver?
    }

    private var observers: [WeakObserver] = []
    private(set) var sent: [JSONValue] = []

    func start() async throws {}
    func close() async {}
    func sendMessage(_ msg: JSONValue) async { sent.append(msg) }
    func sendError(_ error: SignalingError) async {}
    func checkAlive() async {}

    func addObserver(_ observer: SignalingClientObserver) {
        observers.append(WeakObserver(value: observer))
    }

    func removeObserver(_ observer: SignalingClientObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
    }

    /// Deliver a raw message to the observers, as the real client does,
    /// awaiting each observer in turn.
    func deliver(_ message: JSONValue) async {
        for observer in observers.compactMap({ $0.value }) {
            await observer.signalingClient(self, didGetMessage: message)
        }
    }

    func deliverSignaling(_ message: SignalingMessage) async {
        await deliver(signed(message))
    }
}

/// A signaling message as the device sends it with the "none" signer.
private func signed(_ message: SignalingMessage) -> JSONValue {
    signed(message.toJson())
}

/// A raw signaling message as the device sends it with the "none" signer.
private func signed(_ message: JSONValue) -> JSONValue {
    .object(["type": .string("NONE"), "message": message])
}

/// A one-shot latch an observer callback can be held on.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor RecordingObserver: MessageTransportObserver {
    /// One entry per callback, in the order the callbacks were entered.
    private(set) var events: [String] = []
    /// "+name" when a callback is entered, "-name" when it returns, and notes.
    private(set) var log: [String] = []
    private(set) var iceServers: [[SignalingIceServer]] = []
    private(set) var errors: [Error] = []
    private let setupGate: Gate?
    private var onMessage: (@Sendable (MessageTransport, String) async -> Void)?

    init(holdSetupOn gate: Gate? = nil) {
        self.setupGate = gate
    }

    func setOnMessage(_ action: @escaping @Sendable (MessageTransport, String) async -> Void) {
        onMessage = action
    }

    func note(_ entry: String) {
        log.append(entry)
    }

    func messageTransport(_ transport: MessageTransport, didGet message: WebrtcSignalingMessage) async {
        let sdp = message.description?.description.sdp ?? "?"
        enter("message:\(sdp)")
        await onMessage?(transport, sdp)
        log.append("-message:\(sdp)")
    }

    func messageTransport(_ transport: MessageTransport, didError error: Error) async {
        enter("error")
        errors.append(error)
        log.append("-error")
    }

    func messageTransport(_ transport: MessageTransport, didFinishSetup iceServers: [SignalingIceServer]) async {
        enter("setup")
        self.iceServers.append(iceServers)
        await setupGate?.wait()
        log.append("-setup")
    }

    private func enter(_ name: String) {
        events.append(name)
        log.append("+\(name)")
    }
}

extension ClientMessageTransportImpl {
    /// Wait until no delivery loop is running: Everything deliverable has
    /// been delivered.
    fileprivate func waitIdle() async {
        while let task = drainTask {
            await task.value
        }
    }

    fileprivate func pendingCount() -> Int {
        pending.count
    }

    /// Add and remove an observer in one actor turn, so no delivery task
    /// can run in between.
    fileprivate func addThenRemove(_ observer: MessageTransportObserver) {
        addObserver(observer)
        removeObserver(observer)
    }

    /// Add an observer whose last strong reference goes away in the same
    /// actor turn, before any delivery task runs.
    fileprivate func addObserverThatIsReleased() {
        let observer = RecordingObserver()
        addObserver(observer)
    }

    /// Add an observer and receive a live message in one actor turn, so the
    /// live message is queued before the task delivering the held events
    /// has started.
    fileprivate func addObserverAndReceive(_ observer: MessageTransportObserver, _ message: JSONValue, from client: SignalingClient) async {
        addObserver(observer)
        await signalingClient(client, didGetMessage: message)
    }
}

/// Poll until `condition` holds or about two seconds have passed.
private func waitUntil(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<2000 {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return await condition()
}

private let testIceServers = [
    SignalingIceServer(urls: ["stun:stun.example.com"]),
    SignalingIceServer(urls: ["turn:turn.example.com"], credential: "secret", username: "user")
]

private func setupResponse() -> SignalingSetupResponse {
    SignalingSetupResponse(iceServers: testIceServers)
}

/// The error code of a SignalingError, nil for any other error.
private func signalingErrorCode(_ error: Error?) -> String? {
    (error as? SignalingError)?.errorCode.stringValue
}

/// A candidate whose sdpMLineIndex is far outside the range of Int.
private func candidateWithHugeIndex() -> JSONValue {
    .object([
        "type": .string("CANDIDATE"),
        "candidate": .object([
            "candidate": .string("candidate:1 1 udp 1 192.0.2.1 9 typ host"),
            "sdpMLineIndex": .number(1e300)
        ])
    ])
}

private func offer(_ sdp: String) -> SignalingDescription {
    SignalingDescription(type: "offer", sdp: sdp)
}

private func makeTransport(_ client: FakeSignalingClient) async throws -> ClientMessageTransportImpl {
    let transport = try await createClientMessageTransport(client: client, options: .none)
    return transport as! ClientMessageTransportImpl
}

struct ClientMessageTransportTests {
    @Test
    func startSendsSetupRequest() async throws {
        let client = FakeSignalingClient()
        _ = try await makeTransport(client)
        let sent = await client.sent
        #expect(sent.count == 1)
        #expect(sent.first?.asObject?["message"]?.asObject?["type"]?.asString == "SETUP_REQUEST")
    }

    @Test
    func observerAddedBeforeSetupGetsSetupOnce() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        let observer = RecordingObserver()
        await transport.addObserver(observer)

        // The notification returns only after the observer has the event.
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("one"))

        #expect(await observer.log == ["+setup", "-setup", "+message:one", "-message:one"])
        #expect(await observer.iceServers.first?.map(\.urls) == testIceServers.map(\.urls))
    }

    @Test
    func observerAddedAfterSetupGetsSetupWithIceServers() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        await client.deliverSignaling(setupResponse())

        let observer = RecordingObserver()
        await transport.addObserver(observer)
        await transport.waitIdle()

        #expect(await observer.events == ["setup"])
        let received = await observer.iceServers
        #expect(received.count == 1)
        #expect(received.first?.map(\.urls) == testIceServers.map(\.urls))
        #expect(received.first?.last?.username == "user")
        #expect(received.first?.last?.credential == "secret")
    }

    @Test
    func heldSetupAndMessagesReachFirstObserverInOrder() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("one"))
        await client.deliverSignaling(offer("two"))

        let observer = RecordingObserver()
        await transport.addObserver(observer)
        await transport.waitIdle()

        #expect(await observer.events == ["setup", "message:one", "message:two"])
    }

    @Test
    func liveMessageDuringHeldDeliveryQueuesBehindAndWaits() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("held"))

        let gate = Gate()
        let observer = RecordingObserver(holdSetupOn: gate)
        await transport.addObserver(observer)
        #expect(await waitUntil { await observer.log == ["+setup"] })

        // A live message arrives while didFinishSetup is held open.
        let live = Task {
            await client.deliverSignaling(offer("live"))
            await observer.note("returned:live")
        }
        #expect(await waitUntil { await transport.pendingCount() == 2 })
        // While setup is held open the live notification has not returned.
        for _ in 0..<100 { await Task.yield() }
        #expect(await !observer.log.contains("returned:live"))
        await gate.open()
        await live.value

        // No message callback entered while setup was held, the live message
        // came after the held one, and its notification returned only after
        // the observer was done with it.
        #expect(await observer.log == [
            "+setup", "-setup",
            "+message:held", "-message:held",
            "+message:live", "-message:live",
            "returned:live"
        ])
    }

    @Test
    func liveMessageBeforeHeldDeliveryStartsQueuesBehind() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("held"))

        let observer = RecordingObserver()
        await transport.addObserverAndReceive(observer, signed(offer("live")), from: client)

        // The live notification returned only after everything was delivered.
        #expect(await observer.log == [
            "+setup", "-setup",
            "+message:held", "-message:held",
            "+message:live", "-message:live"
        ])
    }

    @Test
    func laterObserverGetsSetupAndNoEarlierMessages() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        let first = RecordingObserver()
        await transport.addObserver(first)
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("one"))

        let second = RecordingObserver()
        await transport.addObserver(second)
        await transport.waitIdle()
        #expect(await second.events == ["setup"])

        // Adding the same observer again does not repeat didFinishSetup.
        await transport.addObserver(second)
        await transport.waitIdle()
        await client.deliverSignaling(offer("two"))

        #expect(await first.events == ["setup", "message:one", "message:two"])
        #expect(await second.events == ["setup", "message:two"])
        #expect(await second.iceServers.first?.map(\.urls) == testIceServers.map(\.urls))
    }

    @Test
    func reAddedDuringAnotherCallbackIsANewRegistration() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        let first = RecordingObserver()
        let second = RecordingObserver()
        await transport.addObserver(first)
        await transport.addObserver(second)
        await client.deliverSignaling(setupResponse())

        // While the first observer handles "one", the second is removed and
        // added again.
        await first.setOnMessage { transport, sdp in
            if sdp == "one" {
                await transport.removeObserver(second)
                await transport.addObserver(second)
            }
        }
        await client.deliverSignaling(offer("one"))
        await client.deliverSignaling(offer("two"))

        #expect(await first.events == ["setup", "message:one", "message:two"])
        // The new registration gets setup, then the next message, and not
        // the message that was in flight when it was added.
        #expect(await second.events == ["setup", "setup", "message:two"])
    }

    @Test
    func errorBeforeAnyObserverReachesFirstObserver() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        // Not a valid signed message: the transport reports a verification error.
        await client.deliver(.string("not a signed message"))

        let observer = RecordingObserver()
        await transport.addObserver(observer)
        await transport.waitIdle()

        #expect(await observer.events == ["error"])
    }

    @Test
    func removedObserverGetsNothing() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("one"))

        let removed = RecordingObserver()
        await transport.addThenRemove(removed)
        await transport.waitIdle()
        #expect(await transport.pendingCount() == 2)

        // The held events stay held for the next observer.
        let next = RecordingObserver()
        await transport.addObserver(next)
        await transport.waitIdle()
        #expect(await next.events == ["setup", "message:one"])
        #expect(await removed.events.isEmpty)
    }

    @Test
    func eventsStayHeldWhenLastObserverIsReleased() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("one"))

        await transport.addObserverThatIsReleased()
        await transport.waitIdle()
        #expect(await transport.pendingCount() == 2)

        let next = RecordingObserver()
        await transport.addObserver(next)
        await transport.waitIdle()
        #expect(await next.events == ["setup", "message:one"])
    }

    @Test
    func closeDuringDeliveryStopsIt() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("one"))

        let gate = Gate()
        let observer = RecordingObserver(holdSetupOn: gate)
        await transport.addObserver(observer)
        #expect(await waitUntil { await observer.log == ["+setup"] })

        await transport.close()
        await gate.open()
        await transport.waitIdle()

        #expect(await observer.log == ["+setup", "-setup"])
        #expect(await transport.pendingCount() == 0)
    }

    @Test
    func closeDropsHeldEventsAndDeliversNothing() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("one"))

        await transport.close()
        let observer = RecordingObserver()
        await transport.addObserver(observer)
        // A message that was already on its way when close was called.
        await transport.signalingClient(client, didGetMessage: signed(offer("two")))
        await transport.waitIdle()

        #expect(await observer.events.isEmpty)
        #expect(await transport.pendingCount() == 0)
    }

    @Test
    func setupResponseWithoutIceServersFinishesSetupWithNone() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        let observer = RecordingObserver()
        await transport.addObserver(observer)

        // A device whose own ICE server request failed omits the member.
        await client.deliver(signed(.object(["type": .string("SETUP_RESPONSE")])))
        await client.deliverSignaling(offer("one"))

        #expect(await observer.events == ["setup", "message:one"])
        #expect(await observer.iceServers.map(\.count) == [0])
    }

    @Test
    func setupResponseWithNullIceServersFinishesSetupWithNone() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        await client.deliver(signed(.object(["type": .string("SETUP_RESPONSE"), "iceServers": .null])))
        await client.deliverSignaling(offer("one"))

        let observer = RecordingObserver()
        await transport.addObserver(observer)
        await transport.waitIdle()

        #expect(await observer.events == ["setup", "message:one"])
        #expect(await observer.iceServers.map(\.count) == [0])
    }

    @Test
    func malformedSetupResponseIsAnError() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        // Held before any observer, like every other event.
        await client.deliver(signed(.object([
            "type": .string("SETUP_RESPONSE"),
            "iceServers": .string("stun:stun.example.com")
        ])))

        let observer = RecordingObserver()
        await transport.addObserver(observer)
        await transport.waitIdle()

        #expect(await observer.events == ["error"])
        #expect(signalingErrorCode(await observer.errors.first) == "DECODE_ERROR")

        // The transport is still waiting for a setup response it can use.
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("one"))
        #expect(await observer.events == ["error", "setup", "message:one"])
    }

    @Test
    func signalingMessageBeforeSetupResponseIsAnError() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        let observer = RecordingObserver()
        await transport.addObserver(observer)

        await client.deliverSignaling(offer("early"))
        await client.deliverSignaling(SignalingCandidate(candidate: "candidate:1 1 udp 1 192.0.2.1 9 typ host"))
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("one"))

        // Neither early message is held or delivered as a message.
        #expect(await observer.events == ["error", "error", "setup", "message:one"])
        let codes = await observer.errors.map { signalingErrorCode($0) }
        #expect(codes == ["DECODE_ERROR", "DECODE_ERROR"])
    }

    @Test
    func undecodableCandidateBeforeSetupResponseIsAnError() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        let observer = RecordingObserver()
        await transport.addObserver(observer)

        await client.deliver(signed(candidateWithHugeIndex()))
        await client.deliverSignaling(setupResponse())
        await client.deliverSignaling(offer("one"))

        #expect(await observer.events == ["error", "setup", "message:one"])
        #expect(signalingErrorCode(await observer.errors.first) == "DECODE_ERROR")
    }

    @Test
    func undecodableCandidateAfterSetupIsDropped() async throws {
        let client = FakeSignalingClient()
        let transport = try await makeTransport(client)
        let observer = RecordingObserver()
        await transport.addObserver(observer)

        await client.deliverSignaling(setupResponse())
        await client.deliver(signed(candidateWithHugeIndex()))
        await client.deliverSignaling(offer("one"))

        #expect(await observer.events == ["setup", "message:one"])
    }
}
