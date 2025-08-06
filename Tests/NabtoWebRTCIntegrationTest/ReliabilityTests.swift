import Testing
import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
@testable import NabtoWebRTC
@testable import NabtoWebRTCUtil

struct ReliabilityTests {
    let clientTestInstance: ClientTestInstance
    let signalingClient: SignalingClient
    let testObject = TestObject()
    let testObjectEncodedAsJsonValue: JSONValue

    init() async throws {
        testObjectEncodedAsJsonValue = try JSONValueEncoder().encode(testObject)
        clientTestInstance = try await ClientTestInstance.create()
        signalingClient = await clientTestInstance.createSignalingClient()
    }

    @Test("RT1 Test messages can be sent by a peer")
    func reliability_test1() async throws {
        try await signalingClient.start()
        try await clientTestInstance.expectConnectionStates([.connecting, .connected])
        try await clientTestInstance.connectDevice()
        await signalingClient.sendMessage(testObjectEncodedAsJsonValue)
        try await clientTestInstance.waitForDeviceToReceiveMessages(messages: [TestObject()], timeoutMillis: 1000)
    }

    @Test("RT2 Test messages can be received by a peer")
    func reliability_test2() async throws {
        try await signalingClient.start()
        try await clientTestInstance.expectConnectionStates([.connecting, .connected])
        try await clientTestInstance.connectDevice()
        try await clientTestInstance.sendMessageToClient([TestObject()])
        try await clientTestInstance.expectMessages([TestObject()])
    }

    @Test("RT3 Test retransmission of messages when peer is comes online")
    func reliability_test3() async throws {
        try await signalingClient.start()
        try await clientTestInstance.expectConnectionStates([.connecting, .connected])
        await signalingClient.sendMessage(testObjectEncodedAsJsonValue)
        try await clientTestInstance.connectDevice()
        try await clientTestInstance.waitForDeviceToReceiveMessages(messages: [TestObject()], timeoutMillis: 1000)
    }

    @Test("RT4 Test resending messages lost on stale websocket")
    func reliability_test4() async throws {
        try await signalingClient.start()
        try await clientTestInstance.connectDevice()
        try await clientTestInstance.expectConnectionStates([.connecting, .connected])
        await signalingClient.sendMessage(testObjectEncodedAsJsonValue)
        try await clientTestInstance.waitForDeviceToReceiveMessages(messages: [TestObject()], timeoutMillis: 1000)
        try await clientTestInstance.dropClientMessages()
        await signalingClient.sendMessage(testObjectEncodedAsJsonValue)
        await signalingClient.checkAlive()
        try await clientTestInstance.waitForDeviceToReceiveMessages(messages: [TestObject(), TestObject()], timeoutMillis: 1000)
    }

    @Test("RT5 Test remote peer discards duplicates")
    func reliability_test5() async throws {
        try await signalingClient.start()
        try await clientTestInstance.connectDevice()
        try await clientTestInstance.dropClientMessages()
        try await clientTestInstance.sendMessageToClient([testObject])
        try await clientTestInstance.expectMessages([testObject])
        await signalingClient.checkAlive()
        let testObject2 = TestObject(foo: "2")
        try await clientTestInstance.sendMessageToClient([testObject2])
        try await clientTestInstance.expectMessages([testObject2])
    }

    @Test("RT6 Test remote peer resends unacked messages")
    func reliability_test6() async throws {
        try await signalingClient.start()
        try await clientTestInstance.connectDevice()
        try await clientTestInstance.dropDeviceMessages()
        await signalingClient.sendMessage(testObjectEncodedAsJsonValue)
        try await clientTestInstance.disconnectDevice()
        try await clientTestInstance.connectDevice()
        try await clientTestInstance.waitForDeviceToReceiveMessages(messages: [testObject], timeoutMillis: 1000)
    }
}