import Foundation
import NabtoWebRTC

/**
 * Observer protocol for MessageTransport
 */
public protocol MessageTransportObserver: AnyObject {
    /**
     * Callback invoked when a message is received from the Camera.
     *
     * @param transport The MessageTransport that received the message
     * @param message The received message.
     */
    func messageTransport(_ transport: MessageTransport, didGet message: WebrtcSignalingMessage) async

    /**
     * Callback invoked if an error occurs in the MessageTransport.
     *
     * Before setup has finished, a message from the device that is not a
     * usable setup response (a malformed setup response, or a description or
     * candidate sent ahead of it) is reported here as a SignalingError with
     * the code decodeError. The message is dropped and the transport keeps
     * waiting for the setup response.
     *
     * @param transport The MessageTransport that emitted the error
     * @param error The error that occurred.
     */
    func messageTransport(_ transport: MessageTransport, didError error: Error) async

    /**
     * Callback invoked when the setup phase of the MessageTransport is concluded.
     *
     * The list of ICE servers may be empty, for example when the device could
     * not obtain ICE servers. This is a normal outcome: Create the Peer
     * Connection with the empty list.
     *
     * @param transport The MessageTransport that finished its setup phase.
     * @param iceServers A list of ICE servers to use in Peer Connection, possibly empty.
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
 * with the RTC ICE Servers provided in the callback, which may be none.
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
     * An observer may be added at any time after the transport is created.
     * Events that arrive while no observer is registered (the setup event,
     * signaling messages and errors) are held and delivered, in the order
     * they arrived, once an observer is added. An observer added after setup
     * has finished receives didFinishSetup with the same ICE servers and then
     * the events from then on. Adding an observer that is already registered
     * has no effect. An observer that is removed and added again is a new
     * registration and receives didFinishSetup again.
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
     *
     * @param sharedSecret The shared secret to use
     * @param keyID Optional key ID for the secret.
     */
    case sharedSecret(sharedSecret: String, keyId: String? = nil)
}

/**
 * Create a client MessageTransport. The type of signing to be used depends on the options parameter.
 *
 * The transport sends its setup request before this function returns, so the
 * setup response and the first messages may arrive before the application
 * calls addObserver on the returned transport. They are not lost: They are
 * held and delivered once an observer is added (see MessageTransport.addObserver).
 * The transport delivers events one at a time, so the signaling client must not
 * deliver an incoming message from inside its sendMessage: An observer callback
 * may be awaiting that send.
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
