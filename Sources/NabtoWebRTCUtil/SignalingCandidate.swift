import NabtoWebRTC

/**
 * SignalingMessage struct representing an ICE candidate sent through the message transport.
 */
public struct SignalingCandidate: Codable, SignalingMessage {
    /**
     * Candidate information struct definition
     */
    public struct Candidate: Codable {
        /**
         * The string representation of the candidate
         */
        public var candidate: String

        /**
         * Optional SDP MID of the candidate.
         */
        public var sdpMid: String?

        /**
         * Optional SDP M Line Index of the candidate.
         */
        public var sdpMLineIndex: Int?

        /**
         * Optional Username Fragment of the candidate.
         */
        public var usernameFragment: String?
    }

    public var type = SignalingMessageType.candidate

    /**
     * Field containing the information in the candidate.
     */
    public var candidate: Candidate

   /**
     * Initialize a Candidate to be sent by the MessageTransport.
     *
     * @param candidate The string representation of the candidate.
     * @param sdpMid Optional SDP MID value.
     * @param sdpMLineIndex Optional SDP M Line Index.
     * @param usernameFragment Optional Username Fragment.
     */
    public init(
        candidate: String,
        sdpMid: String? = nil,
        sdpMLineIndex: Int? = nil,
        usernameFragment: String? = nil
    ) {
        self.candidate = Candidate(
            candidate: candidate,
            sdpMid: sdpMid,
            sdpMLineIndex: sdpMLineIndex,
            usernameFragment: usernameFragment
        )
    }

    /**
     * Convert the candidate to JSON.
     *
     * @return The resulting JSON object.
     */
    public func toJson() -> JSONValue {
        var jsonCandidate: [String: JSONValue] = [:]
        jsonCandidate["candidate"] = .string(candidate.candidate)

        if let sdpMid = candidate.sdpMid {
            jsonCandidate["sdpMid"] = .string(sdpMid)
        }

        if let sdpMLineIndex = candidate.sdpMLineIndex {
            jsonCandidate["sdpMLineIndex"] = .number(Double(sdpMLineIndex))
        }

        if let usernameFragment = candidate.usernameFragment {
            jsonCandidate["usernameFragment"] = .string(usernameFragment)
        }

        return JSONValue.object([
            "type": .string(type.rawValue),
            "candidate": .object(jsonCandidate)
        ])
    }

    /**
     * Create a candidate from a JSON object.
     *
     * @param json The JSON representation.
     * @return The resulting Candidate object.
     */
    public static func fromJson(_ json: JSONValue) -> SignalingCandidate? {
        guard let candidate = json.asObject?["candidate"]?.asObject?["candidate"]?.asString else {
            return nil
        }

        let sdpMid = json.asObject?["candidate"]?.asObject?["sdpMid"]?.asString
        let sdpMLineIndex = json.asObject?["candidate"]?.asObject?["sdpMLineIndex"]?.asNumber
        let usernameFragment = json.asObject?["candidate"]?.asObject?["usernameFragment"]?.asString

        return SignalingCandidate(
            candidate: candidate,
            sdpMid: sdpMid,
            sdpMLineIndex: Int(sdpMLineIndex ?? 0),
            usernameFragment: usernameFragment
        )
    }
}
