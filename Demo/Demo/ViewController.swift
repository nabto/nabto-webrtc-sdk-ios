//
//  ViewController.swift
//  Demo
//
//  Created by Ahmad Saleh on 05/05/2025.
//

import NabtoWebRTC
import NabtoWebRTCUtil
import UIKit
import WebRTC

let productId = "wp-z3nyma7y"
let deviceId = "wd-wbnx9pat7xifmbuh"
let sharedSecret = "MySecret"

class ViewController: UIViewController {
    // WebRTC
    var videoView: RTCMTLVideoView!
    var factory: RTCPeerConnectionFactory! = nil
    var peerConnection: RTCPeerConnection! = nil
    var remoteTrack: RTCVideoTrack! = nil
    var polite = false
    var makingOffer = false
    var ignoreOffer = false

    // Nabto Signaling
    var signalingClient: SignalingClient? = nil
    let signer = JWTMessageSigner(sharedSecret: sharedSecret, keyId: "default")

    func initPeerConnectionFactory() {
        //RTCSetMinDebugLogLevel(.info)
        //RTCEnableMetrics()
        RTCInitializeSSL()

        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        videoView = RTCMTLVideoView(frame: self.view.frame)
        videoView.videoContentMode = .scaleAspectFit
        embedView(videoView, into: self.view)

        initPeerConnectionFactory()

        signalingClient = createSignalingClient(
            SignalingClientOptions(
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

    private func embedView(_ view: UIView, into container: UIView) {
        container.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false

        container.addConstraints(
            NSLayoutConstraint.constraints(
                withVisualFormat: "H:|[view]|",
                options: [],
                metrics: nil,
                views: ["view": view]
            ))

        container.addConstraints(
            NSLayoutConstraint.constraints(
                withVisualFormat: "V:|[view]|",
                options: [],
                metrics: nil,
                views: ["view": view]
            ))

        container.layoutIfNeeded()
    }

    private func onClientConnected() {
        guard let signalingClient = signalingClient else {
            // Impossible code branch
            fatalError("onClientConnected was called but signalingClient is nil")
        }

        let jsonEncoder = JSONEncoder()
        let setupRequestMessage = SignalingSetupRequest()
        let signed = try! signer.signMessage(setupRequestMessage.toJson())

        signalingClient.addObserver(self)
        signalingClient.sendMessage(signed)
    }

    private func setupPeerConnection(_ iceServers: [RTCIceServer]) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let config = RTCConfiguration()
        config.iceServers = iceServers

        peerConnection = factory.peerConnection(
            with: config, constraints: constraints, delegate: self)
    }

    private func addIceCandidate(_ cand: SignalingCandidate.Candidate) {
        let remoteCandidate = RTCIceCandidate(
            sdp: cand.candidate, sdpMLineIndex: 0, sdpMid: cand.sdpMid)
        peerConnection.add(
            remoteCandidate,
            completionHandler: { err in
                if let err = err, !self.ignoreOffer {
                    print("addIceCandidate error: \(err)")
                }
            })
    }

    private func setRemoteDescription(_ desc: SignalingDescription.Description) {
        let collision =
            desc.type == "offer" && (makingOffer || peerConnection.signalingState != .stable)

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
                let signalingDescription = SignalingDescription(
                    type: RTCSessionDescription.string(for: desc.type), sdp: desc.sdp)
                let signed = try signer.signMessage(signalingDescription.toJson())
                signalingClient?.sendMessage(signed)
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
            let signed = try signer.signMessage(signalingCandidate.toJson())
            signalingClient?.sendMessage(signed)
        } catch {
            print("sendIceCandidate error: \(error)")
        }
    }
}

extension ViewController: SignalingClientObserver {
    func signalingClient(
        _ client: any NabtoWebRTC.SignalingClient,
        didConnectionStateChange connectionState: NabtoWebRTC.SignalingConnectionState
    ) {
    }

    func signalingClient(_ client: any SignalingClient, didGetMessage message: JSONValue) {
        do {
            let verified = try signer.verifyMessage(message)
            let msg = SignalingMessageUnion.fromJson(verified)

            if let desc = msg.description {
                setRemoteDescription(desc.description)
            }

            if let cand = msg.candidate {
                addIceCandidate(cand.candidate)
            }

            if msg.setupRequest != nil {
                fatalError("Received createRequest but I'm a client?")
            }

            if let response = msg.setupResponse {
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

    func signalingClient(
        _ client: any SignalingClient, didChannelStateChange channelState: SignalingChannelState
    ) {
        print("Signaling channel state changed to \(channelState)")
    }

    func signalingClient(_ client: any SignalingClient, didError error: Error) {
        print("Signaling channel error: \(error)")
    }

    func signalingClientDidSignalingReconnect(_ client: any SignalingClient) {
        print("Signaling reconnect requested")
    }
}

extension ViewController: RTCPeerConnectionDelegate {
    func peerConnection(
        _ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState
    ) {
        print("RTCSignalingState ==> \(stateChanged)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("RTCMediaStream was added")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("RTCMediaStream was removed")
    }

    func peerConnection(
        _ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState
    ) {
        print("RTCIceConnectionState ==> \(newState)")
    }

    func peerConnection(
        _ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState
    ) {
        print("RTCIceGatheringState ==> \(newState)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate)
    {
        sendIceCandidate(candidate)
    }

    func peerConnection(
        _ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]
    ) {
        print("Ice candidates were removed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel \(dataChannel.channelId) was opened")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        self.makingOffer = true
        peerConnection.setLocalDescriptionWithCompletionHandler { err in
            if err == nil {
                self.makingOffer = false
            }
        }
    }

    func peerConnection(
        _ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver,
        streams mediaStreams: [RTCMediaStream]
    ) {
        if let track = rtpReceiver.track {
            switch track {
            case let track as RTCVideoTrack:
                track.add(videoView)
                remoteTrack = track
                break
            case is RTCAudioTrack:
                break
            default:
                print("Track \(track.trackId) was not a video or audio track?")
            }
        }
    }
}
