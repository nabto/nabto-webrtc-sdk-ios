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

    private func applyLocalDescription() async throws {
        // RTCPeerConnection only exposes the implicit (offer-or-answer)
        // setLocalDescription as a blocking async call, so create the local
        // description explicitly via the suspending completion-handler variants
        // and then set it. This mirrors the implicit behavior: answer when we
        // hold a remote offer, otherwise offer.
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let sdp = try await createLocalSessionDescription(constraints: constraints)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnectionQueue.async {
                self.peerConnection.setLocalDescription(sdp, completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
        }
    }

    private func createLocalSessionDescription(constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peerConnectionQueue.async {
                let completion: (RTCSessionDescription?, Error?) -> Void = { sdp, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let sdp {
                        continuation.resume(returning: sdp)
                    } else {
                        continuation.resume(throwing: PerfectNegotiationError.missingLocalDescription)
                    }
                }
                switch self.peerConnection.signalingState {
                case .haveRemoteOffer, .haveLocalPrAnswer:
                    self.peerConnection.answer(for: constraints, completionHandler: completion)
                default:
                    self.peerConnection.offer(for: constraints, completionHandler: completion)
                }
            }
        }
    }

    private func applyRemoteDescription(_ description: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnectionQueue.async {
                self.peerConnection.setRemoteDescription(description, completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
        }
    }

    private func addRemoteCandidate(_ candidate: RTCIceCandidate) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnectionQueue.async {
                self.peerConnection.add(candidate, completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
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
