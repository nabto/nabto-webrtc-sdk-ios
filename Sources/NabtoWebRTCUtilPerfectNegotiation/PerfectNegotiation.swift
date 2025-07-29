import WebRTC
import NabtoWebRTCUtil

class PerfectNegotiation {
    let peerConnection: RTCPeerConnection
    let messageTransport: MessageTransport

    var remoteTrack: RTCVideoTrack! = nil
    var polite = false
    var makingOffer = false
    var ignoreOffer = false

    init(peerConnection: RTCPeerConnection, messageTransport: MessageTransport) {
        self.peerConnection = peerConnection
        self.messageTransport = messageTransport
    }

    public func onNegotiationNeeded() {
        self.makingOffer = true
        peerConnection.setLocalDescriptionWithCompletionHandler { err in
            if err == nil {
                self.makingOffer = false
            }
        }
    }

    public func onIceCandidate(_ candidate: RTCIceCandidate) {
        sendIceCandidate(candidate)
    }

    public func onMessage(_ message: WebrtcSignalingMessage) {
        if let description = message.description?.description {
            setRemoteDescription(description)
        } else if let candidate = message.candidate?.candidate {
            addIceCandidate(candidate)
        }
    }

    private func addIceCandidate(_ cand: SignalingCandidate.Candidate) {
        let remoteCandidate = RTCIceCandidate(sdp: cand.candidate, sdpMLineIndex: 0, sdpMid: cand.sdpMid)
        peerConnection.add(
            remoteCandidate,
            completionHandler: { err in
                if let err = err, !self.ignoreOffer {
                    print("addIceCandidate error: \(err)")
                }
            }
        )
    }

    private func setRemoteDescription(_ desc: SignalingDescription.Description) {
        let collision = desc.type == "offer" && (makingOffer || peerConnection.signalingState != .stable)

        ignoreOffer = !polite && collision
        if ignoreOffer {
            return
        }

        let type = RTCSessionDescription.type(for: desc.type)
        let desc = RTCSessionDescription(type: type, sdp: desc.sdp)

        self.peerConnection.setRemoteDescription(desc) { err in
            if err != nil {
                print("setRemoteDescription failed: \(String(describing: err))")
                return
            }

            self.peerConnection.setLocalDescriptionWithCompletionHandler { err in
                if err != nil {
                    print("setLocalDescription failed: \(String(describing: err))")
                    return
                }

                self.sendDescription(self.peerConnection.localDescription)
            }
        }
    }

    private func sendDescription(_ desc: RTCSessionDescription?) {
        do {
            if let desc = desc {
                let signalingDescription = SignalingDescription(type: RTCSessionDescription.string(for: desc.type), sdp: desc.sdp)
                try messageTransport.sendWebrtcSignalingMessage(.init(description: signalingDescription))
            }
        } catch {
            print("sendDescription error: \(error)")
        }
    }

    private func sendIceCandidate(_ iceCandidate: RTCIceCandidate) {
        do {
            let signalingCandidate = SignalingCandidate(
                candidate: iceCandidate.sdp,
                sdpMid: iceCandidate.sdpMid,
                sdpMLineIndex: Int(iceCandidate.sdpMLineIndex)
            )
            try messageTransport.sendWebrtcSignalingMessage(.init(candidate: signalingCandidate))
        } catch {
            print("sendIceCandidate error: \(error)")
        }
    }
}
