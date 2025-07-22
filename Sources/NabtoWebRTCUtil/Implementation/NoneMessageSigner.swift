import NabtoWebRTC

public class NoneMessageSigner: MessageSigner {
    public func signMessage(_ message: JSONValue) throws -> JSONValue {
        return JSONValue.object([
            "type": JSONValue.string("NONE"),
            "message": message
        ])
    }

    public func verifyMessage(_ token: JSONValue) throws -> JSONValue {
        guard let type = token.asObject?["type"]?.asString else {
            throw SignalingError(errorCode: .verificationError, errorMessage: "Expected key 'type' on signing message was not found")
        }

        if type == "NONE" {
            guard let result = token.asObject?["message"] else {
                throw SignalingError(errorCode: .verificationError, errorMessage: "Expected key 'message' on signing message was not found")
            }
            return result
        } else {
            throw SignalingError(errorCode: SignalingErrorCode.verificationError, errorMessage: "Expected a signing message of type NONE but got \(type)")
        }
    }
}
