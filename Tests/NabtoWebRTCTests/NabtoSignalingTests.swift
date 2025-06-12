import XCTest
@testable import NabtoWebRTC
@testable import NabtoWebRTCUtil

final class NabtoSignalingTests: XCTestCase {
    func testMessageSigning() throws {
        let message = JSONValue.string("Hello World")
        let signer = JWTMessageSigner(sharedSecret: "MySecret", keyId: "default")
        let signed = try signer.signMessage(message)
        let verified = try signer.verifyMessage(signed)
        XCTAssertEqual(message, verified)
    }

    func testBackend() async throws {
        let backend = Backend(endpointUrl: "https://eu.webrtc.nabto.net", productId: "wp-apy9i4ab", deviceId: "wd-fxb4zxg7nyf7sf3w")
        let response = try await backend.doClientConnect(nil)
        print(response.channelId, response.signalingUrl)
    }

    func testJson() async throws {
        let json = JSONValue.object([
            "foo": JSONValue.array([JSONValue.number(1), JSONValue.number(2)]),
            "bar": JSONValue.bool(true)
        ])

        let encoded = try JSONEncoder().encode(json)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)
    }
}
