import Foundation

public class MessageDecoder {
    public init() {}

    public func decodeMessage(_ msg: String) -> SignalingMessageUnion {
        let decoder = JSONDecoder()
        let data = msg.data(using: .utf8)!

        struct PossibleSignalingMessage: Codable {
            var type: SignalingMessageType
        }

        let possibleMessage = try? decoder.decode(PossibleSignalingMessage.self, from: data)
        var result = SignalingMessageUnion()
        
        switch possibleMessage?.type {
            case .candidate:
                result.candidate = try? decoder.decode(SignalingCandidate.self, from: data)
            case .createRequest:
                result.createRequest = try? decoder.decode(SignalingCreateRequest.self, from: data)
            case .createResponse:
                result.createResponse = try? decoder.decode(SignalingCreateResponse.self, from: data)
            case .description:
                result.description = try? decoder.decode(SignalingDescription.self, from: data)
            case nil:
                break
        }

        return result
    }
}
