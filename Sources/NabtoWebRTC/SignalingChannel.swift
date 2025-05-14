/**
 * Hint about the state of the remote peer. The state is only updated in
 * certain situations and in some cases it does not reflect the actual state
 * of the remote peer.
 */
public enum SignalingChannelState : String {
    case new = "NEW"
    case online = "ONLINE"
    case offline = "OFFLINE"
    case failed = "FAILED"
    case closed = "CLOSED"
}

/**
 * Observer interface for SignalingChannel callbacks
 */
public protocol SignalingChannelObserver: AnyObject {
    /**
     * SignalingChannel received a message from the camera
     * @param channel The SignalingChannel that received the message
     * @param message The received message
     */
    func signalingChannel(_ channel: SignalingChannel, didGetMessage message: String)

    /**
     * SignalingChannel state changed
     * @param channel The SignalingChannel whose state changed
     * @param channelState The new SignalingChannelState
     */
    func signalingChannel(_ channel: SignalingChannel, didChannelStateChange channelState: SignalingChannelState)

    /**
     * SignalingChannel got an error
     * @param channel The SignalingChannel that the error occurred on
     * @param error The SignalingError that occurred
     */
    func signalingChannel(_ channel: SignalingChannel, didSignalingError error: SignalingError)

    /**
     * SignalingChannel reconnected
     * @param channel The SignalingChannel that reconnected
     */
    func signalingChannelDidSignalingReconnect(_ channel: SignalingChannel)
}

/**
 * SignalingChannel represents a logical channel to the camera through the underlying websocket relay connection.
 */
public protocol SignalingChannel {
    /**
     * The current state of the SignalingChannel
     */
    var channelState: SignalingChannelState { get }

    /**
     * Send a message across the channel to the peer
     * @param msg The message to send
     */
    func sendMessage(_ msg: String)

    /**
     * Send an error across the channel to the peer
     * @param errorCode The error code to send
     * öparam errorMessage An optional message to explain the error
     */
    func sendError(errorCode: String, errorMessage: String)

    /**
     * Trigger the underlying SignalingClient to ping the backend to test that the connection is alive.
     *
     * If the connection is dead it will be reconnected.
     * Any result is reported to the observers on their didSignalingError and didSignalingReconnect functions.
     */
    func checkAlive()

    /**
     * Add an observer to this signaling channel.
     * @param observer The observer.
     */
    func addObserver(_ observer: SignalingChannelObserver)

    /**
     * Remove an observer from this signaling channel.
     * @param observer The observer to be removed.
     */
    func removeObserver(_ observer: SignalingChannelObserver)
}
