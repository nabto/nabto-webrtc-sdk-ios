import Foundation

public class MessageDecoder {
    public init() {}

    public func decodeMessage(_ msg: String) -> SignalingMessageUnion {
        let decoder = JSONDecoder()
        let data = msg.data(using: .utf8)!
        return SignalingMessageUnion(
            candidate:      try? decoder.decode(SignalingCandidate.self, from: data),
            createRequest:  try? decoder.decode(SignalingCreateRequest.self, from: data),
            createResponse: try? decoder.decode(SignalingCreateResponse.self, from: data),
            description:    try? decoder.decode(SignalingDescription.self, from: data)
        )
    }
}
