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
    }
    
    func handleConnectionStateChange() async {
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
    
    func handleConnectionReconnect() {
        peerConnection?.restartIce()
    }
}
