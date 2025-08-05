import Testing
import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
@testable import NabtoWebRTC
@testable import NabtoWebRTCUtil

struct ClientDeviceTests {
    let service: ClientTestInstance

    init() async throws {
        service = try await ClientTestInstance.create()
    }

    @Test("CDT1 Test device disconnected")
    func client_device_test1() async throws {
        let client = await service.createSignalingClient()
        try await client.start()
        try await service.expectChannelStates([.disconnected])
    }

    @Test("CDT2 Test device connected")
    func client_device_test2() async throws {
        let client = await service.createSignalingClient()
        try await service.connectDevice()
        try await client.start()
        try await service.expectChannelStates([.connected])
    }

    @Test("CDT3 Test device connecting while client is connected")
    func client_device_test3() async throws {
        let client = await service.createSignalingClient()
        try await client.start()
        try await service.expectChannelStates([.disconnected])
        try await service.expectConnectionStates([.connecting, .connected])
        try await service.connectDevice()
        try await service.expectChannelStates([.connected])
    }

    @Test("CDT4 Test requireOnline bit")
    func client_device_test4() async throws {
        let client = await service.createSignalingClient(requireOnline: true)
        try await client.start()
        try await service.expectChannelStates([.disconnected])
        let error = try await service.expectSomeError()
        #expect(error is SignalingClientError)
    }

    // @TODO: CDT5

    @Test("CDT6 Test sending an error from device")
    func client_device_test6() async throws {
        let client = service.createSignalingClient()
        try client.start()
        try await service.expectConnectionStates([.connecting, .connected])
        try await service.connectDevice()
        try await service.expectChannelStates([.offline, .online])
        
        try await service.sendDeviceError(errorCode: "MyError", errorMessage: "Some error message")
        let error = try await service.expectSomeError()

        guard let signalingError = error as? SignalingError else {
            return
        }

        if case .unknown(let code) = signalingError.errorCode {
            #expect(code == "MyError")
        } else {
            Issue.record("Incorrect signaling error code")
        }
    }
}