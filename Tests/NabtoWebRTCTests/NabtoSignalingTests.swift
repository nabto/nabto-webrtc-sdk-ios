import Testing
@testable import NabtoWebRTC
@testable import NabtoWebRTCUtil

struct NabtoSignalingTests {
    @Test
    func testMessageSigning() throws {
        let message = JSONValue.string("Hello World")
        let signer = JWTMessageSigner(sharedSecret: "MySecret", keyId: "default")
        let signed = try signer.signMessage(message)
        let verified = try signer.verifyMessage(signed)
        #expect(message == verified)
    }
}
