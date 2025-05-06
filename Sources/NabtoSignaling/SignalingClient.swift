public enum SignalingConnectionState: String {
    case new = "NEW"
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
    case waitRetry = "WAIT_RETRY"
    case failed = "FAILED"
    case closed = "CLOSED"
}

public protocol SignalingClientObserver: AnyObject {
    func signalingClient(_ client: SignalingClient, didConnectionStateChange connectionState: SignalingConnectionState)
}

public protocol SignalingClient {
    var signalingChannel: SignalingChannel! { get }
    var connectionState: SignalingConnectionState { get }

    func connect() async throws
    func close()
    func connect(accessToken: String) async throws

    func addObserver(_ observer: SignalingClientObserver)
    func removeObserver(_ observer: SignalingClientObserver)
}

public struct SignalingClientOptions {
    let endpointUrl: String
    let productId: String
    let deviceId: String

    public init(
        endpointUrl: String? = nil,
        productId: String? = nil,
        deviceId: String? = nil
    ) {
        self.endpointUrl = endpointUrl ?? ""
        self.productId = productId ?? ""
        self.deviceId = deviceId ?? ""
    }
}

public func createSignalingClient(_ options: SignalingClientOptions? = nil) -> SignalingClient {
    let opts = options ?? SignalingClientOptions()
    return SignalingClientImpl(endpointUrl: opts.endpointUrl, productId: opts.productId, deviceId: opts.deviceId)
}
