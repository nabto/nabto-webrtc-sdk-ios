import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
@testable import NabtoWebRTC
@testable import NabtoWebRTCUtil

class DictionaryEncoder {
    private let jsonEncoder = JSONEncoder()
    func encode<T>(_ value: T) throws -> Any where T: Encodable {
        let jsonData = try jsonEncoder.encode(value)
        return try JSONSerialization.jsonObject(with: jsonData)
    }
}

class DictionaryDecoder {
    private let jsonDecoder = JSONDecoder()
    func decode<T>(_ type: T.Type, from json: Any) throws -> T where T: Decodable {
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        return try jsonDecoder.decode(type, from: jsonData)
    }
}

struct TestObject: Codable {
    var foo = "test"
}

enum IntegrationTestError: Error {
    case runtimeError(String? = nil)
    case backendError(String? = nil)
    case testFailed(String)
}

class ClientTestInstance {
    private static let apiClient = Client(
        serverURL: URL(string: "http://localhost:13745")!,
        transport: URLSessionTransport()
    )

    static func create(
        failHttp: Bool? = nil,
        failWs: Bool? = nil,
        extraClientConnectResponseData: Bool? = nil,
        requireAccessToken: Bool? = nil
    ) async throws -> ClientTestInstance {
        let response = try await apiClient.postTestClient(body: .json(.init(
            failHttp: failHttp,
            failWs: failWs,
            extraClientConnectResponseData: extraClientConnectResponseData,
            requireAccessToken: requireAccessToken
        )))

        switch response {
            case .ok(let okResponse):
                let productId = try okResponse.body.json.productId
                let deviceId = try okResponse.body.json.deviceId
                let endpointUrl = try okResponse.body.json.endpointUrl
                let testId = try okResponse.body.json.testId
                let accessToken = try? okResponse.body.json.accessToken
                return ClientTestInstance(
                    productId: productId,
                    deviceId: deviceId,
                    endpointUrl: endpointUrl,
                    testId: testId,
                    accessToken: accessToken
                )
            default:
                throw IntegrationTestError.backendError("Missing response data")
        }
    }

    let productId: String
    let deviceId: String
    let endpointUrl: String
    let testId: String
    let accessToken: String

    let (connectionStateStream, connectionStateContinuation) = AsyncStream.makeStream(of: SignalingConnectionState.self)
    let (channelStateStream, channelStateContinuation) = AsyncStream.makeStream(of: SignalingChannelState.self)
    let (messageStream, messageContinuation) = AsyncStream.makeStream(of: JSONValue.self)
    let (errorStream, errorContinuation) = AsyncStream.makeStream(of: Error.self)

    init(
        productId: String,
        deviceId: String,
        endpointUrl: String,
        testId: String,
        accessToken: String?
    ) {
        self.productId = productId
        self.deviceId = deviceId
        self.endpointUrl = endpointUrl
        self.testId = testId
        self.accessToken = accessToken ?? ""
    }

    func createSignalingClient(requireOnline: Bool? = nil, accessToken: String? = nil) async -> SignalingClient {
        let signalingClient = NabtoWebRTC.createSignalingClient(SignalingClientOptions(
            productId: productId,
            deviceId: deviceId,
            endpointUrl: endpointUrl,
            requireOnline: requireOnline,
            accessToken: accessToken
        ))

        await signalingClient.addObserver(self)
        return signalingClient
    }

    func expectConnectionStates(_ expectedStates: [SignalingConnectionState]) async throws {
        var states = expectedStates
        for await state in connectionStateStream {
            let expectedState = states.removeFirst()
            if state != expectedState {
                throw IntegrationTestError.testFailed("expected connection state to be \(expectedState) but got state \(state)")
            }

            if states.isEmpty {
                break
            }
        }
    }

    func expectChannelStates(_ expectedStates: [SignalingChannelState]) async throws {
        var states = expectedStates
        for await state in channelStateStream {
            let expectedState = states.removeFirst()
            if state != expectedState {
                throw IntegrationTestError.testFailed("expected channel state to be \(expectedState) but got state \(state)")
            }

            if states.isEmpty {
                break
            }
        }
    }

    func expectMessages(_ expectedMessages: [TestObject]) async throws {
        var messages = expectedMessages
        for await message in messageStream {
            let expectedMessage = try JSONValueEncoder().encode(messages.removeFirst())
            if message != expectedMessage {
                throw IntegrationTestError.testFailed("expected message to be \(expectedMessage) but got \(message)")
            }

            if messages.isEmpty {
                break
            }
        }
    }

    func expectSomeError() async throws -> Error {
        for await error in errorStream {
            return error
        }
        throw IntegrationTestError.runtimeError("Impossible code path reached")
    }

    func waitForDeviceToReceiveMessages(messages: [TestObject], timeoutMillis: Double) async throws {
        let enc = DictionaryEncoder()
        let res = try await Self.apiClient.postTestClientByTestIdWaitForDeviceMessages(
            path: .init(testId: self.testId),
            body: .json(.init(
                messages: try messages.map { try OpenAPIValueContainer(unvalidatedValue: try enc.encode($0)) },
                timeout: timeoutMillis
            ))
        )
        switch res {
            case .ok:
                break
            default:
                throw IntegrationTestError.backendError()
        }
    }

    func waitForDeviceError(timeoutMillis: Double) async throws -> String? {
        let res = try await Self.apiClient.postTestClientByTestIdWaitForDeviceError(
            path: .init(testId: self.testId),
            body: .json(.init(timeout: timeoutMillis))
        )
        return try? res.ok.body.json.error?.code
    }

    func sendDeviceError(errorCode: String, errorMessage: String) async throws {
        let res = try await Self.apiClient.postTestClientByTestIdSendDeviceError(
            path: .init(testId: self.testId),
            body: .json(.init(errorCode: errorCode, errorMessage: errorMessage))
        )
        guard case .ok = res else {
            throw IntegrationTestError.backendError()
        }
    }

    func sendMessageToClient(_ messages: [TestObject]) async throws {
        let enc = DictionaryEncoder()
        let res = try await Self.apiClient.postTestClientByTestIdSendDeviceMessages(
            path: .init(testId: self.testId),
            body: .json(.init(
                messages: try messages.map { try OpenAPIValueContainer(unvalidatedValue: try enc.encode($0)) }
            ))
        )

        guard case .ok = res else {
            throw IntegrationTestError.backendError()
        }
    }

    func sendUnknownWebsocketMessageType() async throws {
        let res = try await Self.apiClient.postTestClientByTestIdSendNewMessageType(
            path: .init(testId: self.testId),
            body: .json(.init(unvalidatedValue: [:]))
        )
        
        guard case .ok = res else {
            throw IntegrationTestError.backendError()
        }
    }

    func sendNewFieldInKnownMessageType() async throws {
        let res = try await Self.apiClient.postTestClientByTestIdSendNewFieldInKnownMessageType(
            path: .init(testId: self.testId),
            body: .json(.init(unvalidatedValue: [:]))
        )
        
        guard case .ok = res else {
            throw IntegrationTestError.backendError()
        }
    }

    func dropClientMessages() async throws {
        let res = try await Self.apiClient.postTestClientByTestIdDropClientMessages(
            path: .init(testId: self.testId)
        )

        guard case .ok = res else {
            throw IntegrationTestError.backendError()
        }
    }

    func dropDeviceMessages() async throws {
        let res = try await Self.apiClient.postTestClientByTestIdDropDeviceMessages(
            path: .init(testId: self.testId)
        )

        guard case .ok = res else {
            throw IntegrationTestError.backendError()
        }
    }

    func getActiveWebSockets() async throws -> Int {
        let res = try await Self.apiClient.postTestClientByTestIdGetActiveWebsockets(
            path: .init(testId: self.testId),
            body: .json(.init(unvalidatedValue: [:]))
        )

        return Int(try res.ok.body.json.activeWebSockets)
    }

    func closeWebsocket() async throws {
        let res = try await Self.apiClient.postTestClientByTestIdDisconnectClient(
            path: .init(testId: self.testId)
        )
        guard case .ok = res else {
            throw IntegrationTestError.backendError()
        }
    }

    func destroyTest() async throws {
        let response = try await Self.apiClient.deleteTestClientByTestId(path: .init(testId: self.testId))
        switch response {
            case .ok:
                break
            default:
                throw IntegrationTestError.backendError()
        }
    }

    func connectDevice() async throws {
        let response = try await Self.apiClient.postTestClientByTestIdConnectDevice(path: .init(testId: self.testId))
        switch response {
            case .ok:
                break
            default:
                throw IntegrationTestError.backendError()
        }
    }

    func disconnectDevice() async throws {
        let res = try await Self.apiClient.postTestClientByTestIdDisconnectDevice(path: .init(testId: self.testId))
        guard case .ok = res else {
            throw IntegrationTestError.backendError()
        }
    }
}

extension ClientTestInstance: SignalingClientObserver {
    func signalingClient(_ client: any NabtoWebRTC.SignalingClient, didConnectionStateChange connectionState: NabtoWebRTC.SignalingConnectionState) async {
        connectionStateContinuation.yield(connectionState)
    }

    func signalingClient(_ client: any NabtoWebRTC.SignalingClient, didChannelStateChange channelState: NabtoWebRTC.SignalingChannelState) async {
        channelStateContinuation.yield(channelState)
    }

    func signalingClient(_ client: any NabtoWebRTC.SignalingClient, didGetMessage message: NabtoWebRTC.JSONValue) async {
        messageContinuation.yield(message)
    }

    func signalingClient(_ client: any NabtoWebRTC.SignalingClient, didError error: any Error) async {
        errorContinuation.yield(error)
    }

    func signalingClientDidConnectionReconnect(_ client: any NabtoWebRTC.SignalingClient) async {}
}
