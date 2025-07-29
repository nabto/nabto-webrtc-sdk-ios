import NabtoWebRTC

public struct SignalingDescription: Codable, SignalingMessage {
    public struct Description: Codable {
        public var type: String
        public var sdp: String
    }

    public var type = SignalingMessageType.description
    public var description: Description

    public init(
        type: String,
        sdp: String
    )  {
        self.description = Description(type: type, sdp: sdp)
    }

    public func toJson() -> JSONValue {
        return .object([
            "type": .string(type.rawValue),
            "description": .object([
                "type": .string(description.type),
                "sdp": .string(description.sdp)
            ])
        ])
    }

    public static func fromJson(_ json: JSONValue) -> SignalingDescription? {
        guard let jsonDescType = json.asObject?["description"]?.asObject?["type"]?.asString else {
            return nil
        }

        guard let jsonDescSdp = json.asObject?["description"]?.asObject?["sdp"]?.asString else {
            return nil
        }

        return SignalingDescription(
            type: jsonDescType,
            sdp: jsonDescSdp
        )
    }
}
