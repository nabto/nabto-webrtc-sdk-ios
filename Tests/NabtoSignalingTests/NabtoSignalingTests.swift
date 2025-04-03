import XCTest
@testable import NabtoSignaling

final class NabtoSignalingTests: XCTestCase {
    func testExample() throws {
        let message = "Hello World"
        let signer = SharedSecretMessageSigner(sharedSecret: "MySecret", keyId: "default")
        let signed = try signer.signMessage(message)
        let verified = try signer.verifyMessage(signed)
        XCTAssertEqual(message, verified)
    }
}
