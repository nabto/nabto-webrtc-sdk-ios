enum SignalingConnectionState: String {
    case new = "NEW"
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
    case waitRetry = "WAIT_RETRY"
    case failed = "FAILED"
    case closed = "CLOSED"
}

protocol SignalingClientObserver: AnyObject {
    func signalingClient(_ client: SignalingClient, didConnectionStateChange connectionState: SignalingConnectionState)
}

protocol SignalingClient {
    var signalingChannel: SignalingChannel! { get }
    var connectionState: SignalingConnectionState { get }

    func connect() async throws
    func close()
    func connect(accessToken: String) async throws

    func addObserver(_ observer: SignalingClientObserver)
    func removeObserver(_ observer: SignalingClientObserver)
}
