/**
 * The different states a signaling client may be in.
 * A signaling client always starts in the "new" state.
 */
public enum SignalingConnectionState: String {
    case new = "NEW"
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
    case waitRetry = "WAIT_RETRY"
    case failed = "FAILED"
    case closed = "CLOSED"
}

/**
 * Observer interface for SignalingClient callbacks
 */
public protocol SignalingClientObserver: AnyObject {
    /**
     * SignalingClient had its connection state change
     * @param client The SignalingClient whose state has changed
     * @param connectionState The new state that the SignalingClient is in
     */
    func signalingClient(_ client: SignalingClient, didConnectionStateChange connectionState: SignalingConnectionState)
}

/**
 * SignalingClient represents the clientside signaling connection
 * through the Nabto WebRTC signaling service.
 */
public protocol SignalingClient {
    /**
     * The signaling channel that can be used to communicate with a camera peer.
     */
    var signalingChannel: SignalingChannel! { get }

    /**
     * The current connection state of the client.
     */
    var connectionState: SignalingConnectionState { get }

    /**
     * Asynchronously attempt to make an anonymous connection to the signaling service.
     */
    func connect() async throws

    /**
     * Asynchronously attempt to make an authorized connection to the signaling service.
     * @param accessToken Access token that will be used to establish an authorized connection.
     */
    func connect(accessToken: String) async throws

    /**
     * Close the signaling client.
     * This will send a CHANNEL_CLOSED message to the peer before closing the underlying websocket connection.
     */
    func close()

    /**
     * Add an observer to this signaling client.
     * @param observer The observer.
     */
    func addObserver(_ observer: SignalingClientObserver)

    /**
     * Remove an observer from this signaling client.
     * @param observer The observer to be removed.
     */
    func removeObserver(_ observer: SignalingClientObserver)
}

/**
 * This struct is used in createSignalingClient() to set product ID, device ID and other options for the client connection.
 */
public struct SignalingClientOptions {
    let endpointUrl: String
    let productId: String
    let deviceId: String
    let requireOnline: Bool

    public init(
        productId: String,
        deviceId: String,
        endpointUrl: String? = nil,
        requireOnline: Bool? = nil
    ) {
        self.productId = productId
        self.deviceId = deviceId
        self.endpointUrl = endpointUrl ?? "https://\(self.productId).webrtc.nabto.net"
        self.requireOnline = requireOnline ?? false
    }
}

/**
 * Creates a signaling client
 * @param options A SignalingClientOptions struct with connection information.
 */
public func createSignalingClient(_ options: SignalingClientOptions) -> SignalingClient {
    let opts = options
    return SignalingClientImpl(endpointUrl: opts.endpointUrl, productId: opts.productId, deviceId: opts.deviceId, requireOnline: opts.requireOnline)
}
