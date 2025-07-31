import NabtoWebRTC

public struct SignalingCandidate: Codable, SignalingMessage {
    public struct Candidate: Codable {
        public var candidate: String
        public var sdpMid: String?
        public var sdpMLineIndex: Int?
        public var usernameFragment: String?
    }

    public var type = SignalingMessageType.candidate
    public var candidate: Candidate

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