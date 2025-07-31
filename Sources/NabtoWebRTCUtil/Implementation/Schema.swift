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
