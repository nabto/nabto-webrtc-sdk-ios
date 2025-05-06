//
//  ViewController.swift
//  Demo
//
//  Created by Ahmad Saleh on 05/05/2025.
//

import UIKit
import WebRTC
import NabtoSignaling

let endpointUrl = "https://eu.webrtc.nabto.net"
let productId = "wp-apy9i4ab"
let deviceId = "wd-fxb4zxg7nyf7sf3w"
let sharedSecret = "MySecret"

class ViewController: UIViewController {
    @IBOutlet weak var videoScreenView: UIView!

    // WebRTC
    var videoView: RTCMTLVideoView!
    var factory: RTCPeerConnectionFactory! = nil
    var peerConnection: RTCPeerConnection! = nil
    var polite = false
    var makingOffer = false
    var ignoreOffer = false

    // Nabto Signaling
    var signalingClient: SignalingClient? = nil
    let decoder = MessageDecoder()
    let signer = SharedSecretMessageSigner(sharedSecret: sharedSecret, keyId: "default")

    func initPeerConnectionFactory() {
        RTCSetMinDebugLogLevel(.info)
        RTCEnableMetrics()
        RTCInitializeSSL()

        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        videoView = RTCMTLVideoView(frame: videoScreenView.frame)
        videoView.videoContentMode = .scaleAspectFit
        addVideoView(into: videoScreenView)

        initPeerConnectionFactory()

        signalingClient = createSignalingClient(SignalingClientOptions(
            endpointUrl: endpointUrl,
            productId: productId,
            deviceId: deviceId
        ))

        Task {
            do {
                try await signalingClient?.connect()
                self.onClientConnected()
            } catch {
                print("Error occurred in connect \(error)")
            }
        }
    }

    private func addVideoView(into container: UIView) {
        container.addSubview(videoView)
        videoView.translatesAutoresizingMaskIntoConstraints = false
        container.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "H:|[view]|",
            options: [],
            metrics: nil,
            views: ["view": self]
        ))

        container.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "V:|[view]|",
            options: [],
            metrics: nil,
            views: ["view": self]
        ))

        container.layoutIfNeeded()
    }

    private func onClientConnected() {
        guard let signalingClient = signalingClient else {
            // Impossible code branch
            fatalError("onClientConnected was called but signalingClient is nil")
        }

        let jsonEncoder = JSONEncoder()
        let createRequestMessage = SignalingCreateRequest()
        let msg = String(data: try! jsonEncoder.encode(createRequestMessage), encoding: .utf8)!
        let signed = try! signer.signMessage(msg)

        signalingClient.signalingChannel.addObserver(self)
        signalingClient.signalingChannel.sendMessage(signed)
    }

    private func setupPeerConnection(_ iceServers: [RTCIceServer]) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let config = RTCConfiguration()
        config.iceServers = iceServers
        
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
    }

    private func addIceCandidate(_ cand: SignalingCandidate.Candidate) {
        let remoteCandidate = RTCIceCandidate(sdp: cand.candidate, sdpMLineIndex: 0, sdpMid: cand.sdpMid)
        peerConnection.add(remoteCandidate, completionHandler: { err in 
            if let err = err, !self.ignoreOffer {
                print("addIceCandidate error: \(err)")
            }
        })
    }

    private func setRemoteDescription(_ desc: SignalingDescription.Description) {
        let collision = desc.type == "offer" && (makingOffer || peerConnection.signalingState != .stable)

        ignoreOffer = !polite && collision
        if ignoreOffer {
            return
        }

        let type = RTCSessionDescription.type(for: desc.type)
        let desc = RTCSessionDescription(type: type, sdp: desc.sdp)

        Task {
            do {
                try await peerConnection.setRemoteDescription(desc)
                try await peerConnection.setLocalDescription()
                sendDescription(peerConnection.localDescription)
            } catch {
                print("setRemoteDescription failed: \(error)")
            }
        }
    }

    private func sendDescription(_ desc: RTCSessionDescription?) {
        do {
            if let desc = desc {
                let signalingDescription = SignalingDescription(type: RTCSessionDescription.string(for: desc.type), sdp: desc.sdp)
                let jsonData = try JSONEncoder().encode(signalingDescription)
                let json = String(data: jsonData, encoding: .utf8)!
                let signed = try signer.signMessage(json)
                signalingClient?.signalingChannel.sendMessage(signed)
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
            let jsonData = try JSONEncoder().encode(signalingCandidate)
            let json = String(data: jsonData, encoding: .utf8)!
            let signed = try signer.signMessage(json)
            signalingClient?.signalingChannel.sendMessage(signed)
        } catch {
            print("sendIceCandidate error: \(error)")
        }
    }
}

extension ViewController: SignalingChannelObserver {
    func signalingChannel(_ channel: any NabtoSignaling.SignalingChannel, didGetMessage message: String) {
        do {
            let verified = try signer.verifyMessage(message)
            let msg = decoder.decodeMessage(verified)
            
            if let desc = msg.description {
                setRemoteDescription(desc.description)
            }

            if let cand = msg.candidate {
                addIceCandidate(cand.candidate)
            }

            if msg.createRequest != nil {
                fatalError("Received createRequest but I'm a client?")
            }

            if let response = msg.createResponse {
                var iceServers: [RTCIceServer] = []
                for iceServer in response.iceServers {
                    let rtcIceServer = RTCIceServer(
                        urlStrings: iceServer.urls,
                        username: iceServer.username,
                        credential: iceServer.credential
                    )
                    iceServers.append(rtcIceServer)
                }

                setupPeerConnection(iceServers)
            }
        } catch {
            print("Error in SignalingChannel didGetMessage: \(error)")
        }
    }

    func signalingChannel(_ channel: any NabtoSignaling.SignalingChannel, didChannelStateChange channelState: NabtoSignaling.SignalingChannelState) {
        print("Signaling channel state changed to \(channelState)")
    }

    func signalingChannel(_ channel: any NabtoSignaling.SignalingChannel, didSignalingError error: NabtoSignaling.SignalingError) {
        print("Signaling chanel error: \(error)")
    }

    func signalingChannelDidSignalingReconnect(_ channel: any NabtoSignaling.SignalingChannel) {
        print("Signaling reconnect requested")
    }
}

extension ViewController: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("RTCSignalingState ==> \(stateChanged)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("RTCMediaStream was added")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("RTCMediaStream was removed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("RTCIceConnectionState ==> \(newState)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("RTCIceGatheringState ==> \(newState)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        sendIceCandidate(candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("Ice candidates were removed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel \(dataChannel.channelId) was opened")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Task {
            makingOffer = true
            try await peerConnection.setLocalDescription()
            makingOffer = false
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let track = rtpReceiver.track {
            switch (track) {
                case is RTCVideoTrack:
                    break
                case is RTCAudioTrack:
                    break
                default:
                    print("Track \(track.trackId) was not a video or audio track?")
            }
        }
    }
}
