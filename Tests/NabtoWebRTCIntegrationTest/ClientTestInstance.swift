import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
@testable import NabtoWebRTC
@testable import NabtoWebRTCUtil

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

    static func create(failHttp: Bool? = nil, failWs: Bool? = nil, extraClientConnectResponseData: Bool? = nil) async throws -> ClientTestInstance {
        let response = try await apiClient.postTestClient(body: .json(.init(
            failHttp: failHttp,
            failWs: failWs,
            extraClientConnectResponseData: extraClientConnectResponseData
        )))

        switch response {
            case .ok(let okResponse):
                let productId = try okResponse.body.json.productId
                let deviceId = try okResponse.body.json.deviceId
                let endpointUrl = try okResponse.body.json.endpointUrl
                let testId = try okResponse.body.json.testId
                return ClientTestInstance(productId: productId, deviceId: deviceId, endpointUrl: endpointUrl, testId: testId)
            default:
                throw IntegrationTestError.backendError("Missing response data")
        }
    }

    let productId: String
    let deviceId: String
    let endpointUrl: String
    let testId: String

    let (connectionStateStream, connectionStateContinuation) = AsyncStream.makeStream(of: SignalingConnectionState.self)

    init(productId: String, deviceId: String, endpointUrl: String, testId: String) {
        self.productId = productId
        self.deviceId = deviceId
        self.endpointUrl = endpointUrl
        self.testId = testId
    }

    // NOTE: this method can hang if connectionStates remains a prefix of expectedStates but never becomes equal.
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

    func destroyTest() async throws {
        let response = try await Self.apiClient.deleteTestClientByTestId(path: .init(testId: self.testId))
        switch response {
            case .ok:
                break
            default:
                throw IntegrationTestError.backendError()
        }
    }

    func createSignalingClient(requireOnline: Bool? = nil) -> SignalingClient {
        let signalingClient = NabtoWebRTC.createSignalingClient(SignalingClientOptions(
            productId: productId,
            deviceId: deviceId,
            endpointUrl: endpointUrl,
            requireOnline: requireOnline
        ))

        signalingClient.addObserver(self)
        return signalingClient
    }

    func waitForObservedStates(client: SignalingClient, states: [SignalingConnectionState]) async throws -> Bool {
        return false
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
}

extension ClientTestInstance: SignalingClientObserver {
    func signalingClient(_ client: any NabtoWebRTC.SignalingClient, didGetMessage message: NabtoWebRTC.JSONValue) {}
    func signalingClient(_ client: any NabtoWebRTC.SignalingClient, didChannelStateChange channelState: NabtoWebRTC.SignalingChannelState) {}
    func signalingClientDidSignalingReconnect(_ client: any NabtoWebRTC.SignalingClient) {}

    func signalingClient(_ client: any NabtoWebRTC.SignalingClient, didError error: any Error) {
        print(error)
    }
    func signalingClient(_ client: any NabtoWebRTC.SignalingClient, didConnectionStateChange connectionState: NabtoWebRTC.SignalingConnectionState) {
        connectionStateContinuation.yield(connectionState)
    }
}
