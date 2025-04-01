import Foundation

struct ClientConnectResponse: Codable {
    var signalingUrl: String
    var deviceOnline: Bool?
    var channelId: String
}

class Backend {
    struct RequestBody: Codable {
        var productId: String
        var deviceId: String
    }

    var endpointUrl: String
    var productId: String
    var deviceId: String

    init(endpointUrl: String, productId: String, deviceId: String) {
        self.endpointUrl = endpointUrl
        self.productId = productId
        self.deviceId = deviceId
    }

    func doClientConnect(_ authToken: String?) async throws -> ClientConnectResponse {
        let requestObject = RequestBody(productId: self.productId, deviceId: self.deviceId)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(requestObject)

        let url = URL(string: self.endpointUrl + "/v1/client/connect")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }

        let (responseData, response) = try await URLSession.shared.data(for: request)
        let clientConnectResponse = try decoder.decode(ClientConnectResponse.self, from: responseData)
        return clientConnectResponse
    }
}