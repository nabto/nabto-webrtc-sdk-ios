import Foundation
import NabtoWebRTCUtil
import WebRTC

fileprivate enum PerfectNegotiationEvent {
    case negotiationNeeded
    case iceCandidate(_ candidate: RTCIceCandidate)
    case message(_ message: WebrtcSignalingMessage)
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

    private var polite = false
    private var makingOffer = false
    private var ignoreOffer = false

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

        Task {
            for await event in eventStream {
                await handleEvent(event)
            }
        }
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
            do {
                try await peerConnection.setLocalDescription()
                self.makingOffer = false
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
        try await peerConnection.add(remoteCandidate)
    }

    private func setRemoteDescription(_ desc: SignalingDescription.Description) async throws {
        let collision = desc.type == "offer" && (makingOffer || peerConnection.signalingState != .stable)

        ignoreOffer = !polite && collision
        if ignoreOffer {
            return
        }

        let type = RTCSessionDescription.type(for: desc.type)
        let desc = RTCSessionDescription(type: type, sdp: desc.sdp)
        try await self.peerConnection.setRemoteDescription(desc)
        try await self.peerConnection.setLocalDescription()
        await self.sendDescription(self.peerConnection.localDescription)
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
