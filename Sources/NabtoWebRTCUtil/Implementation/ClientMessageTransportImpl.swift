import Foundation
import NabtoWebRTC

actor ClientMessageTransportImpl: MessageTransport {
    /// One addObserver call. Removing an observer and adding it again makes a
    /// new registration with a new generation.
    struct Registration {
        weak var observer: MessageTransportObserver?
        let generation: UInt64
        var setupDelivered = false
    }

    enum State {
        case setup, signaling
    }

    enum Event {
        case setupDone([SignalingIceServer])
        case message(WebrtcSignalingMessage)
        case error(Error)
    }

    private var registrations = [ObjectIdentifier: Registration]()
    private var nextGeneration: UInt64 = 0
    private var state = State.setup
    private let client: SignalingClient
    private let messageSigner: MessageSigner

    /// Events not yet delivered, oldest first. The queue needs no bound:
    /// While an observer is registered, the signaling client's notification
    /// of an event waits until the event has been delivered, so live traffic
    /// cannot outrun delivery. Only events that arrive while no observer is
    /// registered accumulate, at the rate the one authenticated peer sends
    /// them and only until an observer is added.
    private(set) var pending: [Event] = []
    /// The ICE servers of the setup response once its event has been
    /// delivered, so an observer added later still gets didFinishSetup.
    private var setupIceServers: [SignalingIceServer]? = nil
    /// The running delivery loop, if any.
    private(set) var drainTask: Task<Void, Never>? = nil
    private var closed = false

    internal init(client: SignalingClient, options: ClientMessageTransportOptions) {
        self.client = client
        switch options {
            case .none:
                self.messageSigner = NoneMessageSigner()
            case .sharedSecret(let sharedSecret, let keyId):
                self.messageSigner = JWTMessageSigner(sharedSecret: sharedSecret, keyId: keyId)
        }
    }

    public func start() async throws {
        await client.addObserver(self)
        try await sendSignalingMessage(SignalingSetupRequest())
    }

    public func close() async {
        closed = true
        pending.removeAll()
        await client.removeObserver(self)
    }

    public func addObserver(_ observer: any MessageTransportObserver) {
        let id = ObjectIdentifier(observer)
        if let existing = registrations[id], existing.observer === observer {
            return
        }
        nextGeneration += 1
        registrations[id] = Registration(observer: observer, generation: nextGeneration)
        if !pending.isEmpty || setupIceServers != nil {
            // addObserver is synchronous, so a task delivers what is due.
            _ = startDrain()
        }
    }

    public func removeObserver(_ observer: any MessageTransportObserver) {
        let id = ObjectIdentifier(observer)
        registrations.removeValue(forKey: id)
    }

    public func sendWebrtcSignalingMessage(_ message: WebrtcSignalingMessage) async throws {
        if let candidate = message.candidate {
            try await sendSignalingMessage(candidate)
        } else if let description = message.description {
            try await sendSignalingMessage(description)
        }
    }

    private func sendSignalingMessage(_ message: SignalingMessage) async throws {
        let encoded = message.toJson()
        let signed = try messageSigner.signMessage(encoded)
        await client.sendMessage(signed)
    }

    private func handleMessage(_ message: JSONValue) async {
        guard !closed else {
            return
        }
        do {
            let verified = try messageSigner.verifyMessage(message)
            let decoded = SignalingMessageUnion.fromJson(verified)
            switch state {
                case .setup:
                    if let setupResponse = decoded.setupResponse {
                        self.state = .signaling
                        pending.append(.setupDone(setupResponse.iceServers))
                    }
                case .signaling:
                    if let candidate = decoded.candidate {
                        pending.append(.message(WebrtcSignalingMessage(candidate: candidate)))
                    } else if let description = decoded.description {
                        pending.append(.message(WebrtcSignalingMessage(description: description)))
                    }
            }
        } catch {
            pending.append(.error(error))
        }
        await startDrain()?.value
    }

    /**
     * Return the running delivery loop, or start one.
     *
     * Invariant: At most one loop runs at a time and it delivers `pending`
     * strictly from the head. An event that arrives while the loop is
     * suspended in an observer callback is appended behind the held events
     * and delivered by that loop, never ahead of them. The loop runs until
     * the queue is empty, no observer is registered or the transport is
     * closed, and handleMessage awaits it: While an observer is registered,
     * the notification of a live event does not return before that event
     * has been delivered. Neither the loop's exit nor this check suspends,
     * so an event appended after the loop has exited starts a new one.
     */
    private func startDrain() -> Task<Void, Never>? {
        if let task = drainTask {
            return task
        }
        guard !closed else {
            return nil
        }
        let task = Task { [weak self] () -> Void in
            await self?.drain()
        }
        drainTask = task
        return task
    }

    private func drain() async {
        defer { drainTask = nil }
        while !closed {
            registrations = registrations.filter { $0.value.observer != nil }

            // An observer added after setup gets didFinishSetup before
            // anything else. The strong references are taken in one pass, so
            // an observer released meanwhile cannot let a queued event pass
            // a live observer that still waits for setup.
            if let iceServers = setupIceServers,
               let waiting = registrations
                   .compactMap({ id, registration in
                       registration.setupDelivered ? nil : registration.observer.map {
                           (id: id, generation: registration.generation, observer: $0)
                       }
                   })
                   .min(by: { $0.generation < $1.generation }) {
                registrations[waiting.id]?.setupDelivered = true
                await waiting.observer.messageTransport(self, didFinishSetup: iceServers)
                continue
            }

            guard let event = pending.first else {
                break
            }
            // Take strong references before the event leaves the queue: With
            // no live observer it stays held for the next one.
            let recipients = registrations
                .compactMap { id, registration in
                    registration.observer.map { (id: id, generation: registration.generation, observer: $0) }
                }
                .sorted { $0.generation < $1.generation }
            guard !recipients.isEmpty else {
                break
            }
            pending.removeFirst()

            switch event {
                case .setupDone(let iceServers):
                    // The next iterations deliver it to every observer.
                    setupIceServers = iceServers
                case .message(let message):
                    for recipient in recipients where isActive(recipient.id, recipient.generation) {
                        await recipient.observer.messageTransport(self, didGet: message)
                    }
                case .error(let error):
                    for recipient in recipients where isActive(recipient.id, recipient.generation) {
                        await recipient.observer.messageTransport(self, didError: error)
                    }
            }
        }
    }

    /// Whether this registration still stands. Checked right before each
    /// callback, since an earlier callback may have removed or re-added the
    /// observer or closed the transport.
    private func isActive(_ id: ObjectIdentifier, _ generation: UInt64) -> Bool {
        return !closed && registrations[id]?.generation == generation
    }
}

extension ClientMessageTransportImpl: SignalingClientObserver {
    public func signalingClient(_ client: any SignalingClient, didConnectionStateChange connectionState: SignalingConnectionState) async {

    }

    public func signalingClient(_ client: any SignalingClient, didGetMessage message: JSONValue) async {
        await handleMessage(message)
    }

    public func signalingClient(_ client: any SignalingClient, didChannelStateChange channelState: SignalingChannelState) async {

    }

    public func signalingClient(_ client: any SignalingClient, didError error: any Error) async {

    }

    public func signalingClientDidConnectionReconnect(_ client: any SignalingClient) async {

    }
}
