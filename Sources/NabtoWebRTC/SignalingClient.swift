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
 * Hint about the state of the remote peer. The state is only updated in
 * certain situations and in some cases it does not reflect the actual state
 * of the remote peer.
 */
public enum SignalingChannelState : String {
    case new = "NEW"
    // TODO use connected/disconnected as in the js sdk
    case online = "ONLINE"
    case offline = "OFFLINE"
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

    /**
     * SignalingClient received a message from the camera
     * @param client The SignalingClient that received the message
     * @param message The received message
     */
    func signalingClient(_ client: SignalingClient, didGetMessage message: JSONValue)

    /**
     * SignalingClient channel state changed
     * @param client The SignalingClient whose state changed
     * @param channelState The new SignalingChannelState
     */
    func signalingClient(_ client: SignalingClient, didChannelStateChange channelState: SignalingChannelState)

    /**
     * SignalingClient got an error
     * @param client The SignalingClient that the error occurred on
     * @param error The error that occurred
     */
    func signalingClient(_ client: SignalingClient, didError error: Error)

    /**
     * SignalingClient reconnected
     * @param client The SignalingClient that reconnected
     */
     // TODO the name in the JS SDK is on("connectionreconnect") not on("signalingreconnect")
    func signalingClientDidSignalingReconnect(_ client: SignalingClient)
}

/**
 * SignalingClient represents the clientside signaling connection
 * through the Nabto WebRTC signaling service.
 */
public protocol SignalingClient {
    /**
     * The current connection state of the client.
     */
    var connectionState: SignalingConnectionState { get }

    /**
     * The current channel state of the client.
     */
    var channelState: SignalingChannelState { get }

    /**
     * TODO fix docs
     * Asynchronously attempt to make an anonymous connection to the signaling service.
     */
    func start() throws

    /**
     * Close the signaling client.
     * This will send a CHANNEL_CLOSED message to the peer before closing the underlying websocket connection.
     */
    func close()

    /**
     * Send a message across to the peer
     * @param msg The message to send
     */
    func sendMessage(_ msg: JSONValue)

    /**
     * Send an error across to the peer
     * @param errorCode The error code to send
     * //TODO @
     * öparam errorMessage An optional message to explain the error
     */
    // TODO: use sendError(error: SignalingError)
    func sendError(errorCode: String, errorMessage: String)

    /**
     * Trigger a ping to the backend to test that the connection is alive.
     *
     * If the connection is dead it will be reconnected.
     * Any result is reported to the observers on their didSignalingError and didSignalingReconnect functions.
     */
    // TODO indentation
     func checkAlive()

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
 * Represents errors that can occur in SignalingClient
 */
public enum SignalingClientError: Error {
    case connectError(String)
    case runtimeError(String)
}

/**
 * This struct is used in createSignalingClient() to set product ID, device ID and other options for the client connection.
 */
public struct SignalingClientOptions {
    let endpointUrl: String
    let productId: String
    let deviceId: String
    let requireOnline: Bool
    let accessToken: String?

    public init(
        productId: String,
        deviceId: String,
        endpointUrl: String? = nil,
        requireOnline: Bool? = nil,
        accessToken: String? = nil
    ) {
        self.productId = productId
        self.deviceId = deviceId
        self.endpointUrl = endpointUrl ?? "https://\(self.productId).webrtc.nabto.net"
        self.requireOnline = requireOnline ?? false
        self.accessToken = accessToken
    }
}

/**
 * Creates a signaling client
 * @param options A SignalingClientOptions struct with connection information.
 */
public func createSignalingClient(_ options: SignalingClientOptions) -> SignalingClient {
    let opts = options
    return SignalingClientImpl(
        endpointUrl: opts.endpointUrl,
        productId: opts.productId,
        deviceId: opts.deviceId,
        requireOnline: opts.requireOnline,
        accessToken: opts.accessToken
    )
}
