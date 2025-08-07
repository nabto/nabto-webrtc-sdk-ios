import Testing
import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
@testable import NabtoWebRTC
@testable import NabtoWebRTCUtil

struct ClientConnectivityTests {
    let service: ClientTestInstance
    let client: SignalingClient

    init() async throws {
        service = try await ClientTestInstance.create()
        client = await service.createSignalingClient()
    }

    @Test("CCT1 Test client can connect to service")
    func client_connectivity_test1() async throws {
        try await client.start()
        try await service.expectConnectionStates([.connecting, .connected])
    }

    @Test("CCT2 Test client close switches state")
    func client_connectivity_test2() async throws {
        try await client.start()
        try await service.expectConnectionStates([.connecting, .connected])
        await client.close()
        try await service.expectConnectionStates([.closed])
    }
}

struct ClientConnectivityTestsFailOptions {

    @Test("CCT3 Test early failure on HTTP error")
    func client_connectivity_test3() async throws {
        let service = try await ClientTestInstance.create(failHttp: true)
        let client = await service.createSignalingClient()
        try await client.start()
        try await service.expectConnectionStates([.connecting, .failed])
        let _ = try await service.expectSomeError()
    }

    @Test("CCT4 Test early failure on websocket error")
    func client_connectivity_test4() async throws {
        let service = try await ClientTestInstance.create(failWs: true)
        let client = await service.createSignalingClient()
        try await client.start()
        try await service.expectConnectionStates([.connecting, .failed])
        let _ = try await service.expectSomeError()
    }

    @Test("CCT5 Test signaling service reconnection")
    func client_connectivity_test5() async throws {
        let service = try await ClientTestInstance.create()
        let client = await service.createSignalingClient()
        try await client.start()
        try await service.expectConnectionStates([.connecting, .connected])
        try await service.closeWebsocket()
        try await service.expectConnectionStates([
            .waitRetry,
            .connecting,
            .connected
        ])
    }

    @Test("CCT6 Test HTTP protocol extensibility")
    func client_connectivity_test6() async throws {
        let service = try await ClientTestInstance.create(extraClientConnectResponseData: true)
        let client = await service.createSignalingClient()
        try await client.start()
        try await service.expectConnectionStates([.connecting, .connected])
    }

    @Test("CCT7 Test websocket protocol extensibility with new message types")
    func client_connectivity_test7() async throws {
        let service = try await ClientTestInstance.create()
        let client = await service.createSignalingClient()
        try await client.start()
        try await service.expectConnectionStates([.connecting, .connected])
        try await service.sendUnknownWebsocketMessageType()
        try await service.connectDevice()
        try await service.sendMessageToClient([TestObject()])
        try await service.expectMessages([TestObject()])
    }

    @Test("CCT8 Test websocket protocol extensibility with new fields in known message types")
    func client_connectivity_test8() async throws {
        let service = try await ClientTestInstance.create()
        let client = await service.createSignalingClient()
        try await client.start()
        try await service.expectConnectionStates([.connecting, .connected])
        try await service.sendNewFieldInKnownMessageType()
        try await service.connectDevice()
        try await service.sendMessageToClient([TestObject()])
        try await service.expectMessages([TestObject()])
    }

    @Test("CCT9 Test closing of websocket connections on service reconnect")
    func client_connectivity_test9() async throws {
        let service = try await ClientTestInstance.create()
        let client = await service.createSignalingClient()
        try await client.start()
        try await service.expectConnectionStates([.connecting, .connected])
        try await service.dropClientMessages()
        await client.checkAlive()
        try await service.expectConnectionStates([
            .waitRetry,
            .connecting,
            .connected
        ])
        let activeSockets = try await service.getActiveWebSockets()
        #expect(activeSockets == 1)
    }

    @Test("CCT13 Test valid access token")
    func client_connectivity_test13() async throws {
        let service = try await ClientTestInstance.create(requireAccessToken: true)
        let client = await service.createSignalingClient(accessToken: service.accessToken)
        try await client.start()
        try await service.expectConnectionStates([.connecting, .connected])
    }

    @Test("CCT14 Test invalid access token")
    func client_connectivity_test14() async throws {
        let service = try await ClientTestInstance.create(requireAccessToken: true)
        let client = await service.createSignalingClient(accessToken: "invalid")
        try await client.start()
        try await service.expectConnectionStates([.connecting, .failed])
        let error = try await service.expectSomeError()
        #expect(error is HttpError)
    }
}
