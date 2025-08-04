//
//  ViewController.swift
//  Demo
//
//  Created by Ahmad Saleh on 05/05/2025.
//

import NabtoWebRTC
import NabtoWebRTCUtil
import NabtoWebRTCUtilPerfectNegotiation
import UIKit
import WebRTC

let productId = "wp-39wu7tex"
let deviceId = "wd-3xtqp3hy4xxy3av3"
let sharedSecret = "59470b3f8e331d9975da366d8dc0dcf743ef6a1154a4f779932740b4d14be3ab"

class ViewController: UIViewController {
    // WebRTC
    var videoView: RTCMTLVideoView!
    var factory: RTCPeerConnectionFactory! = nil
    var peerConnection: RTCPeerConnection! = nil
    var remoteTrack: RTCVideoTrack! = nil
    var perfectNegotiation: PerfectNegotiation! = nil

    // Nabto Signaling
    var signalingClient: SignalingClient? = nil
    var messageTransport: MessageTransport? = nil
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

        Task {
            signalingClient = createSignalingClient(
                SignalingClientOptions(
                    productId: productId,
                    deviceId: deviceId
                )
            )

            do {
                messageTransport = try await createClientMessageTransport(
                    client: signalingClient!,
                    options: .sharedSecret(sharedSecret: sharedSecret)
                )
                messageTransport?.addObserver(self)
                try await signalingClient?.start()
            } catch {
                print(error)
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

    private func setupPeerConnection(_ iceServers: [SignalingIceServer]) {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let config = RTCConfiguration()
        config.iceServers = iceServers.map { iceServer in
            RTCIceServer(
                urlStrings: iceServer.urls,
                username: iceServer.username,
                credential: iceServer.credential
            )
        }

        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        perfectNegotiation = PerfectNegotiation(peerConnection: peerConnection, messageTransport: messageTransport!)
    }
}

extension ViewController: MessageTransportObserver {
    func messageTransport(_ transport: any MessageTransport, didGet message: WebrtcSignalingMessage) async {
        perfectNegotiation.onMessage(message)
    }

    func messageTransport(_ transport: any MessageTransport, didError error: any Error) async {
        print("MessageTransport error: \(error)")
    }

    func messageTransport(_ transport: any MessageTransport, didFinishSetup iceServers: [SignalingIceServer]) async {
        setupPeerConnection(iceServers)
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

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("Ice candidates were removed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel \(dataChannel.channelId) was opened")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate)
    {
        perfectNegotiation.onIceCandidate(candidate)
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        perfectNegotiation.onNegotiationNeeded()
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
