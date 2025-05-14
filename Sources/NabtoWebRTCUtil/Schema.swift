import Foundation

public enum SignalingMessageType: String, Codable {
    case description = "DESCRIPTION"
    case candidate = "CANDIDATE"
    case createRequest = "CREATE_REQUEST"
    case createResponse = "CREATE_RESPONSE"
}

public struct SignalingIceServer: Codable {
    public var urls: [String]
    public var credential: String?
    public var username: String?

    public init(
        urls: [String],
        credential: String? = nil,
        username: String? = nil
    ) {
        self.urls = urls
        self.credential = credential
        self.username = username
    }
}

public struct SignalingCandidate: Codable {
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
}

public struct SignalingCreateRequest: Codable {
    public var type = SignalingMessageType.createRequest

    public init() {}
}

public struct SignalingCreateResponse: Codable {
    public var type = SignalingMessageType.createResponse
    public var iceServers: [SignalingIceServer]

    public init(iceServers: [SignalingIceServer]) {
        self.iceServers = iceServers
    }
}

public struct SignalingDescription: Codable {
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
}

public struct SignalingMessageUnion {
    public var candidate: SignalingCandidate? = nil
    public var createRequest: SignalingCreateRequest? = nil
    public var createResponse: SignalingCreateResponse? = nil
    public var description: SignalingDescription? = nil

    public static func fromJson(_ msg: String) -> SignalingMessageUnion {
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
