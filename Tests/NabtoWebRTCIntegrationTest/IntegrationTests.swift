import XCTest
import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
@testable import NabtoWebRTC
@testable import NabtoWebRTCUtil

final class ClientConnectTests: XCTestCase {
    var testInstance: ClientTestInstance! = nil

    override func setUp() async throws {
        testInstance = try await ClientTestInstance.create()
    }

    override func tearDown() async throws {
        try await testInstance.destroyTest()
    }

    func testOk() async throws {
        let client = testInstance.createSignalingClient()
        try await client.connect()
    }

    func testConnectionStateSwitchesToCloseAfterCallingClose() async throws {
        let client = testInstance.createSignalingClient()
        try await client.connect()
        try await testInstance.expectConnectionStates([.connecting, .connected])
        client.close()
        try await testInstance.expectConnectionStates([.waitRetry])
    }
}

final class FailHttpTests: XCTestCase {
    var testInstance: ClientTestInstance! = nil

    override func setUp() async throws {
        testInstance = try await ClientTestInstance.create(failHttp: true)
    }

    override func tearDown() async throws {
        try await testInstance.destroyTest()
    }

    func testHttpServiceReturnsBadRequest() async throws {
        let client = testInstance.createSignalingClient()
        XCTAssertEqual(client.connectionState, .new)
        do {
            try await client.connect()
            XCTFail("Expected client.connect() to fail")
        } catch {
            // @TODO: Currently client.connect() fails here because it tries to decode an invalid response.
            // While the act of failing is correct, it should be explicitly handled.
            XCTFail("Failing on purpose, read comment above")
        }

    }
}
