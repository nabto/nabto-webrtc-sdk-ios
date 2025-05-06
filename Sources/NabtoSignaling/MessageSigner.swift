import SwiftJWT

public protocol MessageSigner {
    func signMessage(_ message: String) throws -> String
    func verifyMessage(_ token: String) throws -> String
}

public class SharedSecretMessageSigner: MessageSigner {
    struct SharedSecretClaims: Claims {
        var message: String
        var messageSeq: Int
    }

    private var signSeq = 0
    private let keyId: String
    private let sharedSecret: String

    public init(sharedSecret: String, keyId: String) {
        self.keyId = keyId
        self.sharedSecret = sharedSecret
    }

    public func signMessage(_ message: String) throws -> String {
        let seq = signSeq
        signSeq += 1

        let header = Header(typ: "JWT", kid: self.keyId)
        let claims = SharedSecretClaims(message: message, messageSeq: seq)

        var jwt = JWT(header: header, claims: claims)
        let jwtSigner = JWTSigner.hs256(key: self.sharedSecret.data(using: .utf8)!)

        let signed = try jwt.sign(using: jwtSigner)
        return signed
    }
    
    public func verifyMessage(_ token: String) throws -> String {
        let jwtVerifier = JWTVerifier.hs256(key: self.sharedSecret.data(using: .utf8)!)
        let jwt = try JWT<SharedSecretClaims>(jwtString: token, verifier: jwtVerifier)
        return jwt.claims.message
    }
}
