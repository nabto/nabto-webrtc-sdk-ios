import Foundation
import NabtoWebRTC
import SwiftJWT

public protocol MessageSigner {
    func signMessage(_ message: JSONValue) throws -> JSONValue
    func verifyMessage(_ token: JSONValue) throws -> JSONValue
}

public class JWTMessageSigner: MessageSigner {
    struct JWTClaims: Claims {
        var message: JSONValue
        var messageSeq: Int
        var signerNonce: String
        var verifierNonce: String?
    }

    private let keyId: String
    private let sharedSecret: String

    private var nextMessageSignSeq = 0
    private var nextMessageVerifySeq = 0
    private var nonce: String = UUID().uuidString
    private var remoteNonce: String? = nil

    public init(sharedSecret: String, keyId: String) {
        self.keyId = keyId
        self.sharedSecret = sharedSecret
    }

    public func signMessage(_ message: JSONValue) throws -> JSONValue {
        if nextMessageSignSeq != 0 && remoteNonce == nil {
            // @TODO: FatalError is probably not what we want to use
            fatalError("Cannot sign the message with sequence number > 1, as we have not yet received a valid message from the remote peer.")
        }

        let seq = nextMessageSignSeq
        nextMessageSignSeq += 1

        let header = Header(typ: "JWT", kid: self.keyId)
        let claims = JWTClaims(
            message: message,
            messageSeq: seq,
            signerNonce: nonce,
            verifierNonce: remoteNonce
        )

        var jwt = JWT(header: header, claims: claims)
        let jwtSigner = JWTSigner.hs256(key: self.sharedSecret.data(using: .utf8)!)

        let signed = try jwt.sign(using: jwtSigner)
        return JSONValue.object([
            "type": JSONValue.string("JWT"),
            "jwt": JSONValue.string(signed)
        ])
    }
    
    public func verifyMessage(_ token: JSONValue) throws -> JSONValue {
        let jwtVerifier = JWTVerifier.hs256(key: self.sharedSecret.data(using: .utf8)!)
        guard let jwtString = token.asObject?["jwt"]?.asString else {
            throw SignalingError(errorCode: .decodeError, errorMessage: "JWTMessageSigner.verifyMessage failed, token is not a valid JWT object.")
        }
        let jwt = try JWT<JWTClaims>(jwtString: jwtString, verifier: jwtVerifier)

        let messageSeq = jwt.claims.messageSeq
        if messageSeq != nextMessageVerifySeq {
            throw SignalingError(errorCode: .verificationError, errorMessage: "The message sequence number does not match the expected sequence number.")
        }

        let signerNonce = jwt.claims.signerNonce
        let verifierNonce = jwt.claims.verifierNonce
        if messageSeq == 0 {
            remoteNonce = signerNonce
        } else {
            if remoteNonce != signerNonce {
                throw SignalingError(errorCode: .verificationError, errorMessage: "The value of messageSignerNonce does not match the expected value for the session.")
            }

            if nonce != verifierNonce {
                throw SignalingError(errorCode: .verificationError, errorMessage: "The value of messageVerifierNonce does not match the expected value for the session.")
            }
        }

        nextMessageVerifySeq += 1
        return jwt.claims.message
    }
}
