import NabtoWebRTC


// TODO the MessageSigner should not be public.
/**
 * Generic interface for signing JSONValue messages.
 */
public protocol MessageSigner {
    /**
     * Sign a JSONValue
     *
     * @param message The JSONValue to be signed
     * @return The signed JSONValue
     */
    func signMessage(_ message: JSONValue) throws -> JSONValue

    /**
     * Verify and decode a JSONValue
     *
     * @param message The JSONValue to be decoded
     * @return The decoded JSONValue
     */
    func verifyMessage(_ token: JSONValue) throws -> JSONValue
}
