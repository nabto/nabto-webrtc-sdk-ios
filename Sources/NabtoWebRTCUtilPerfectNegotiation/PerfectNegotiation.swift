import Foundation
import NabtoWebRTCUtil
import WebRTC

fileprivate enum PerfectNegotiationEvent {
    case negotiationNeeded
    case iceCandidate(_ candidate: RTCIceCandidate)
    case message(_ message: WebrtcSignalingMessage)
}

fileprivate enum PerfectNegotiationError: Error {
    case missingLocalDescription
}

/// A continuation wrapper that can be resumed at most once, from either the
/// async operation's completion or task cancellation, whichever happens first.
/// Thread-safe via an internal lock; handles cancellation arriving before the
/// continuation is attached.
fileprivate final class CancellableContinuation<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pendingResult: Result<T, Error>?
    private var finished = false

    func attach(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let pendingResult {
            finished = true
            lock.unlock()
            continuation.resume(with: pendingResult)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        if let continuation {
            finished = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            pendingResult = result
            lock.unlock()
        }
    }
}

/**
 * This class implements the <a
 * href="https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Perfect_negotiation">Perfect
 * Negotiation</a> pattern. This implements perfect negotiation for this <a
 * href="https://github.com/stasel/WebRTC">WebRTC library</a>.
 */
public class PerfectNegotiation {
    private let peerConnection: RTCPeerConnection
    private let messageTransport: MessageTransport

    /// Dedicated serial queue on which the (potentially blocking)
    /// RTCPeerConnection operations run, so they never block a Swift
    /// cooperative-pool thread. See the note above `applyLocalDescription`.
    private let peerConnectionQueue = DispatchQueue(
        label: "com.nabto.webrtc.perfectNegotiation.peerConnection")

    private var polite = false
    private var makingOffer = false
    private var ignoreOffer = false
    private var isSettingRemoteAnswerPending = false

    private var eventTask: Task<Void, Never>?
    private var (eventStream, eventContinuation) = AsyncStream.makeStream(of: PerfectNegotiationEvent.self)

    /**
     * Initialize a perfect negotiator for an RTCPeerConnection.
     *
     * @param peerConnection The PeerConnection to negotiate.
     * @param messageTransport The MessageTransport to use for sending/receiving signaling messages.
     */
    public init(peerConnection: RTCPeerConnection, messageTransport: MessageTransport) {
        self.peerConnection = peerConnection
        self.messageTransport = messageTransport

        eventTask = Task {
            for await event in eventStream {
                await handleEvent(event)
            }
        }
    }
    
    deinit {
        // close() should have been called before deinit
        // This is a fallback in case it wasn't
        eventContinuation.finish()
        eventTask?.cancel()
    }

    /// Closes the perfect negotiation, releasing resources and breaking retain cycles.
    /// Must be called before releasing the PerfectNegotiation instance.
    public func close() {
        eventContinuation.finish()
        eventTask?.cancel()
        eventTask = nil
    }

    public func onNegotiationNeeded() {
        eventContinuation.yield(.negotiationNeeded)
    }

    public func onIceCandidate(_ candidate: RTCIceCandidate) {
        eventContinuation.yield(.iceCandidate(candidate))
    }

    public func onMessage(_ message: WebrtcSignalingMessage) {
        eventContinuation.yield(.message(message))
    }

    private func handleEvent(_ event: PerfectNegotiationEvent) async {
        switch event {
        case .negotiationNeeded:
            self.makingOffer = true
            defer { self.makingOffer = false }
            do {
                try await applyLocalDescription()
                await self.sendDescription(self.peerConnection.localDescription)
            } catch {
                // @TODO: Better logging
                print(error)
            }

        case .iceCandidate(let candidate):
            await sendIceCandidate(candidate)

        case .message(let message):
            do {
                if let description = message.description?.description {
                    try await setRemoteDescription(description)
                } else if let candidate = message.candidate?.candidate {
                    try await addIceCandidate(candidate)
                }
            } catch {
                // @TODO: Log to somewhere sensible
                print(error)
            }
        }
    }

    private func addIceCandidate(_ cand: SignalingCandidate.Candidate) async throws {
        let remoteCandidate = RTCIceCandidate(sdp: cand.candidate, sdpMLineIndex: 0, sdpMid: cand.sdpMid)
        do {
            try await addRemoteCandidate(remoteCandidate)
        } catch {
            if !ignoreOffer {
                throw error
            }
        }
    }

    private func setRemoteDescription(_ desc: SignalingDescription.Description) async throws {
        let readyForOffer = !makingOffer && (peerConnection.signalingState == .stable || isSettingRemoteAnswerPending)
        let collision = desc.type == "offer" && !readyForOffer

        ignoreOffer = !polite && collision
        if ignoreOffer {
            return
        }

        let type = RTCSessionDescription.type(for: desc.type)
        let desc = RTCSessionDescription(type: type, sdp: desc.sdp)
        try await applyRemoteDescription(desc)

        // Send answer only if we are receiving an offer
        if type == .offer {
            try await applyLocalDescription()
            await self.sendDescription(self.peerConnection.localDescription)
        }
    }

    // MARK: - Non-blocking peer-connection operations
    //
    // The WebRTC setLocalDescription/setRemoteDescription/add operations block
    // the calling thread until the signaling thread finishes (the `async`
    // overloads suspend nothing, they block, and even the completion-handler
    // overloads do synchronous work on the caller). PerfectNegotiation's event
    // loop runs on the Swift cooperative thread pool, which is fixed size (one
    // thread per core), so each blocking call parks one pool thread. When many
    // PerfectNegotiation instances negotiate at once (for example an NVR client
    // opening many cameras together, especially over a relayed or high-latency
    // path) the pool is exhausted and the app deadlocks: no thread is left to
    // run the continuations that would let the blocked calls finish.
    //
    // The fix runs each peer-connection operation on a dedicated serial queue
    // and suspends the caller on a continuation. Any blocking then lands on our
    // own thread, never a cooperative-pool thread, so the pool stays free.
    //
    // The bridge is also cancellation-aware: If the negotiation task is
    // cancelled while suspended here (for example close() during an in-flight
    // operation), the caller is resumed with CancellationError so the event
    // loop can unwind and the PerfectNegotiation instance can deallocate,
    // rather than waiting for the WebRTC callback (which may be slow or, after
    // the peer connection is closed, never fire). The underlying WebRTC
    // operation cannot be cancelled, so its later callback is ignored. The
    // continuation is resumed exactly once.

    private func applyLocalDescription() async throws {
        // RTCPeerConnection only exposes the implicit (offer-or-answer)
        // setLocalDescription as a blocking async call, so create the local
        // description explicitly via the suspending completion-handler variants
        // and then set it. This mirrors the implicit behavior: Answer when we
        // hold a remote offer, otherwise offer.
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let sdp = try await createLocalSessionDescription(constraints: constraints)
        try await runOnPeerConnectionQueue { [peerConnection] (completion: @escaping (Result<Void, Error>) -> Void) in
            peerConnection.setLocalDescription(sdp, completionHandler: { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            })
        }
    }

    private func createLocalSessionDescription(constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await runOnPeerConnectionQueue { [peerConnection] (completion: @escaping (Result<RTCSessionDescription, Error>) -> Void) in
            let handler: (RTCSessionDescription?, Error?) -> Void = { sdp, error in
                if let error {
                    completion(.failure(error))
                } else if let sdp {
                    completion(.success(sdp))
                } else {
                    completion(.failure(PerfectNegotiationError.missingLocalDescription))
                }
            }
            switch peerConnection.signalingState {
            case .haveRemoteOffer, .haveLocalPrAnswer:
                peerConnection.answer(for: constraints, completionHandler: handler)
            default:
                peerConnection.offer(for: constraints, completionHandler: handler)
            }
        }
    }

    private func applyRemoteDescription(_ description: RTCSessionDescription) async throws {
        try await runOnPeerConnectionQueue { [peerConnection] (completion: @escaping (Result<Void, Error>) -> Void) in
            peerConnection.setRemoteDescription(description, completionHandler: { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            })
        }
    }

    private func addRemoteCandidate(_ candidate: RTCIceCandidate) async throws {
        try await runOnPeerConnectionQueue { [peerConnection] (completion: @escaping (Result<Void, Error>) -> Void) in
            peerConnection.add(candidate, completionHandler: { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            })
        }
    }

    /// Runs `body` on the dedicated peer-connection queue and suspends the
    /// caller until `body` invokes its completion. Cancellation-aware: If the
    /// task is cancelled while suspended, the caller is resumed with
    /// CancellationError and the WebRTC callback (which cannot be cancelled) is
    /// ignored when it later fires. The caller is resumed exactly once.
    /// `body` captures the peer connection rather than self, so a cancelled
    /// negotiation does not keep the PerfectNegotiation instance alive.
    private func runOnPeerConnectionQueue<T>(
        _ body: @escaping (@escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        let state = CancellableContinuation<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                state.attach(continuation)
                peerConnectionQueue.async {
                    body { result in state.resume(with: result) }
                }
            }
        } onCancel: {
            state.resume(with: .failure(CancellationError()))
        }
    }

    private func sendDescription(_ desc: RTCSessionDescription?) async {
        do {
            if let desc = desc {
                let signalingDescription = SignalingDescription(type: RTCSessionDescription.string(for: desc.type), sdp: desc.sdp)
                try await messageTransport.sendWebrtcSignalingMessage(.init(description: signalingDescription))
            }
        } catch {
            print("sendDescription error: \(error)")
        }
    }

    private func sendIceCandidate(_ iceCandidate: RTCIceCandidate) async {
        do {
            let signalingCandidate = SignalingCandidate(
                candidate: iceCandidate.sdp,
                sdpMid: iceCandidate.sdpMid,
                sdpMLineIndex: Int(iceCandidate.sdpMLineIndex)
            )
            try await  messageTransport.sendWebrtcSignalingMessage(.init(candidate: signalingCandidate))
        } catch {
            print("sendIceCandidate error: \(error)")
        }
    }
}
