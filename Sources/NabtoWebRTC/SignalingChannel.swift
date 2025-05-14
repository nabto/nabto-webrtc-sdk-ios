public enum SignalingChannelState : String {
    case new = "NEW"
    case online = "ONLINE"
    case offline = "OFFLINE"
    case failed = "FAILED"
    case closed = "CLOSED"
}

public protocol SignalingChannelObserver: AnyObject {
    func signalingChannel(_ channel: SignalingChannel, didGetMessage message: String)
    func signalingChannel(_ channel: SignalingChannel, didChannelStateChange channelState: SignalingChannelState)
    func signalingChannel(_ channel: SignalingChannel, didSignalingError error: SignalingError)
    func signalingChannelDidSignalingReconnect(_ channel: SignalingChannel)
}

public protocol SignalingChannel {
    var channelState: SignalingChannelState { get }

    func sendMessage(_ msg: String)
    func sendError(errorCode: String, errorMessage: String)
    func checkAlive()

    func addObserver(_ observer: SignalingChannelObserver)
    func removeObserver(_ observer: SignalingChannelObserver)
}