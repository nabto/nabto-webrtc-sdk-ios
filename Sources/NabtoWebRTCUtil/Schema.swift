import Foundation
import NabtoWebRTC

public enum SignalingMessageType: String, Codable {
    case description = "DESCRIPTION"
    case candidate = "CANDIDATE"
    case setupRequest = "SETUP_REQUEST"
    case setupResponse = "SETUP_RESPONSE"
}

public protocol SignalingMessage {
    func toJson() -> JSONValue
}

public struct SignalingIceServer: Codable, SignalingMessage {
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

    public func toJson() -> JSONValue {
        var object: [String: JSONValue] = [:]

        if let credential = credential {
            object["credential"] = .string(credential)
        }

        if let username = username {
            object["username"] = .string(username)
        }

        let mapped = urls.map { url in JSONValue.string(url)}
        object["urls"] = .array(mapped)

        return .object(object)
    }

    public static func fromJson(_ json: JSONValue) -> SignalingIceServer? {
        var urls: [String] = []
        guard let jsonUrls = json.asObject?["urls"]?.asArray else {
            return nil
        }

        for jsonUrl in jsonUrls {
            if let asString = jsonUrl.asString {
                urls.append(asString)
            }
        }

        let credential = json.asObject?["credential"]?.asString
        let username = json.asObject?["username"]?.asString
        return SignalingIceServer(urls: urls, credential: credential, username: username)
    }
}

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

public struct SignalingSetupRequest: Codable, SignalingMessage {
    public var type = SignalingMessageType.setupRequest

    public init() {}

    public func toJson() -> JSONValue {
        return JSONValue.object(["type": JSONValue.string(type.rawValue)])
    }

    public static func fromJson(_ json: JSONValue) -> SignalingSetupRequest? {
        return SignalingSetupRequest()
    }
}

public struct SignalingSetupResponse: Codable, SignalingMessage {
    public var type = SignalingMessageType.setupResponse
    public var iceServers: [SignalingIceServer]

    public init(iceServers: [SignalingIceServer]) {
        self.iceServers = iceServers
    }

    public func toJson() -> JSONValue {
        let jsonIceServers = iceServers.map { iceServer in iceServer.toJson() }
        return .object([
            "type": .string(type.rawValue),
            "iceServers": .array(jsonIceServers)
        ])
    }

    public static func fromJson(_ json: JSONValue) -> SignalingSetupResponse? {
        guard let jsonIceServers = json.asObject?["iceServers"]?.asArray else {
            return nil
        }

        var iceServers: [SignalingIceServer] = []
        for iceServer in jsonIceServers {
            if let signalingIceServer = SignalingIceServer.fromJson(iceServer) {
                iceServers.append(signalingIceServer)
            }
        }

        return SignalingSetupResponse(iceServers: iceServers)
    }
}

public struct SignalingMessageUnion {
    public var candidate: SignalingCandidate? = nil
    public var setupRequest: SignalingSetupRequest? = nil
    public var setupResponse: SignalingSetupResponse? = nil
    public var description: SignalingDescription? = nil

    public static func fromJson(_ msg: JSONValue) -> SignalingMessageUnion {
        var result = SignalingMessageUnion()

        let jsonType = msg.asObject?["type"]?.asString
        if let jsonType = jsonType {
            let type = SignalingMessageType(rawValue: jsonType)

            switch type {
                case .candidate:
                    result.candidate = SignalingCandidate.fromJson(msg)
                case .setupRequest:
                    result.setupRequest = SignalingSetupRequest.fromJson(msg)
                case .setupResponse:
                    result.setupResponse = SignalingSetupResponse.fromJson(msg)
                case .description:
                    result.description = SignalingDescription.fromJson(msg)
                case nil:
                    break
            }
        }

        return result
    }

    public static func fromJsonString(_ msg: String) -> SignalingMessageUnion {
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
            case .setupRequest:
                result.setupRequest = try? decoder.decode(SignalingSetupRequest.self, from: data)
            case .setupResponse:
                result.setupResponse = try? decoder.decode(SignalingSetupResponse.self, from: data)
            case .description:
                result.description = try? decoder.decode(SignalingDescription.self, from: data)
            case nil:
                break
        }

        return result
    }
}

public struct WebrtcSignalingMessage {
    public var candidate: SignalingCandidate?
    public var description: SignalingDescription?

    public init(candidate: SignalingCandidate? = nil, description: SignalingDescription? = nil) {
        self.candidate = candidate
        self.description = description
    }

    public static func fromJson(_ msg: JSONValue) -> WebrtcSignalingMessage {
        let union = SignalingMessageUnion.fromJson(msg)
        return WebrtcSignalingMessage(
            candidate: union.candidate,
            description: union.description
        )
    }

    public static func fromJsonString(_ msg: String) -> WebrtcSignalingMessage {
        let union = SignalingMessageUnion.fromJsonString(msg)
        return WebrtcSignalingMessage(
            candidate: union.candidate,
            description: union.description
        )
    }
}
