import Foundation
import NabtoWebRTC

/**
 * Observer protocol for MessageTransport
 */
public protocol MessageTransportObserver: AnyObject {
    /**
     * Callback invoked when a message is received from the Camera.
     *
     * @param message The received message.
     */
    func messageTransport(_ transport: MessageTransport, didGet message: WebrtcSignalingMessage) async

    /**
     * Callback invoked if an error occurs in the MessageTransport.
     *
     * @param error The error that occurred.
     */
    func messageTransport(_ transport: MessageTransport, didError error: Error) async

    /**
     * Callback invoked when the setup phase of the MessageTransport is concluded.
     *
     * @param iceServers A list of ICE servers to use in Peer Connection.
     */
    func messageTransport(_ transport: MessageTransport, didFinishSetup iceServers: [SignalingIceServer]) async
}

/**
 * The MessageTransport protocol is used as a middleware to encode, validate,
 * sign, and verify messages sent and received on a Signaling Channel.
 *
 * The responsibilities of the Message Transport is to initially setup the
 * channel. When this is done, it is used to exchange WebRTC Signaling Messages
 * between the client and the device.
 *
 * The didFinishSetup event on MessageTransportObserver is fired when the channel is setup. The
 * PeerConnection should be created in this callback and it should be created
 * with the RTC ICE Servers provided in the callback.
 */
public protocol MessageTransport: Actor {
    /**
     * Send a message through the MessageTransport and the signaling channel to the other peer.
     *
     * @param message The message to send.
     */
    func sendWebrtcSignalingMessage(_ message: WebrtcSignalingMessage) async throws

    /**
     * Add an observer to receive callbacks when events occurs.
     *
     * @param observer The observer to add.
     */
    func addObserver(_ observer: MessageTransportObserver)

    /**
     * Remove an observer from the MessageTransport.
     *
     * @param observer The observer to remove.
     */
    func removeObserver(_ observer: MessageTransportObserver)
}

/**
 * ClientMessageTransportOptions is used for specifying
 * which type of message signing should be used when creating a MessageTransport instance.
 */
public enum ClientMessageTransportOptions {
    /**
     * Using none will result in the MessageTransport not implementing message signing.
     */
    case none

    /**
     * Using sharedSecret will result in the MessageTransport using shared secret message signing.
     */
    case sharedSecret(sharedSecret: String, keyId: String? = nil)
}

/**
 * Create a client MessageTransport. The type of signing to be used depends on the options parameter..
 *
 * @param client The signaling client for sending/receiving messages.
 * @param options A ClientMessageTransportOptions object that specifies what type of message signing to use.
 * @return A client MessageTransport instance.
 */
public func createClientMessageTransport(client: SignalingClient, options: ClientMessageTransportOptions) async throws -> MessageTransport {
    let transport = ClientMessageTransportImpl(client: client, options: options)
    try await transport.start()
    return transport
}
