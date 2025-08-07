import WebRTC
import NabtoWebRTC

/**
 * The purpose of this component is to handle signaling events such as signaling
 * reconnects. And react to RTCPeerConnection events which needs to trigger
 * signaling actions such as checkAlive and restartIce.
 */
public class SignalingEventHandler {
    weak var peerConnection: RTCPeerConnection?
    weak var client: SignalingClient?
    
    init(peerConnection: RTCPeerConnection, client: SignalingClient) {
        self.peerConnection = peerConnection
        self.client = client

        client.addObserver(self)
    }

    deinit {
        client?.removeObserver(self)
    }
    
    
    func handlePeerConnectionStateChange() {
        guard let peerConnection = peerConnection else {
            return
        }
        
        if peerConnection.connectionState == .disconnected {
            await client?.checkAlive()
        }
        
        if peerConnection.connectionState == .failed {
            peerConnection.restartIce()
        }
    }

    private func handleSignalingConnectionReconnect() {
        peerConnection?.restartIce()
    }
}


extension SignalingEventHandler: SignalingClientObserver {
    public func signalingClient(_ client: any SignalingClient, didConnectionStateChange connectionState: SignalingConnectionState) async {
        
    }

    public func signalingClient(_ client: any SignalingClient, didGetMessage message: JSONValue) async {

    }

    public func signalingClient(_ client: any SignalingClient, didChannelStateChange channelState: SignalingChannelState) async {
        
    }

    public func signalingClient(_ client: any SignalingClient, didError error: any Error) async {
        
    }

    public func signalingClientDidConnectionReconnect(_ client: any SignalingClient) async {
        self.handleSignalingConnectionReconnect()
    }
}