import Foundation

struct ClientConnectResponse: Codable {
    var signalingUrl: String
    var deviceOnline: Bool?
    var channelId: String
}

struct BackendErrorResponse: Codable {
    var message: String
    var code: String?
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

        let (responseData, res) = try await URLSession.shared.data(for: request)
        guard let response = res as? HTTPURLResponse else {
            throw HttpError.unknown(statusCode: -1, message: "Failed to correctly read HTTP response")
        }
        
        if response.statusCode >= 200 && response.statusCode < 300 {
            guard let clientConnectResponse = try? decoder.decode(ClientConnectResponse.self, from: responseData) else {
                throw HttpError.unknown(statusCode: response.statusCode, message: "OK response but failed to parse response body")
            }
            
            return clientConnectResponse
        } else {
            guard let backendError = try? decoder.decode(BackendErrorResponse.self, from: responseData) else {
                throw HttpError.unknown(statusCode: response.statusCode, message: "Failed to parse error response body")
            }
            
            if backendError.code == "PRODUCT_ID_NOT_FOUND" {
                throw HttpError.poductIdNotFound(statusCode: response.statusCode, message: backendError.message)
            }
            
            if backendError.code == "DEVICE_ID_NOT_FOUND" {
                throw HttpError.deviceIdNotFound(statusCode: response.statusCode, message: backendError.message)
            }
            
            throw HttpError.unknown(statusCode: response.statusCode, message: backendError.message)
        }
    }
}
