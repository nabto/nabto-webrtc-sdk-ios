import NabtoWebRTC

/**
 * Struct representing a WebRTC Description received or to be sent on the
 * MessageTransport.
 */
public struct SignalingDescription: Codable, SignalingMessage {
    /**
     * Description information struct definition
     */
    public struct Description: Codable {
        /**
         * The description type (typically "offer" or "answer")
         */
        public var type: String

        /**
         * SDP of the description.
         */
        public var sdp: String
    }

    public var type = SignalingMessageType.description

    /**
     * Field containing the information in the description.
     */
    public var description: Description

    /**
     * Initialize a SignalingDescription object to send
     *
     * @param type type of the description, typically "offer" or "answer"
     * @param sdp SDP representation of the description.
     */
    public init(
        type: String,
        sdp: String
    )  {
        self.description = Description(type: type, sdp: sdp)
    }

    /**
     * Convert the description to JSON.
     *
     * @return The resulting JSON object.
     */
    public func toJson() -> JSONValue {
        return .object([
            "type": .string(type.rawValue),
            "description": .object([
                "type": .string(description.type),
                "sdp": .string(description.sdp)
            ])
        ])
    }

    /**
     * Create a description from a JSON object.
     *
     * @param json The JSON representation
     * @return The resulting description object.
     */
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
