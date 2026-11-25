import Foundation
import Testing
@testable import NabtoWebRTC
@testable import NabtoWebRTCUtil

private func setupResponseJson(iceServers: JSONValue?) -> JSONValue {
    var object: [String: JSONValue] = ["type": .string("SETUP_RESPONSE")]
    if let iceServers = iceServers {
        object["iceServers"] = iceServers
    }
    return .object(object)
}

private func jsonString(_ json: JSONValue) throws -> String {
    let data = try JSONEncoder().encode(json)
    return String(decoding: data, as: UTF8.self)
}

/// Decode the message through both entry points of SignalingMessageUnion.
private func decodeBothWays(_ json: JSONValue) throws -> (fromJson: SignalingSetupResponse?, fromJsonString: SignalingSetupResponse?) {
    let fromJson = SignalingMessageUnion.fromJson(json).setupResponse
    let fromJsonString = SignalingMessageUnion.fromJsonString(try jsonString(json)).setupResponse
    return (fromJson, fromJsonString)
}

/// Decode the message through the two direct decoders of the type.
private func decodeDirectly(_ json: JSONValue) throws -> (fromJson: SignalingSetupResponse?, decodable: SignalingSetupResponse?) {
    let data = try JSONEncoder().encode(json)
    return (SignalingSetupResponse.fromJson(json), try? JSONDecoder().decode(SignalingSetupResponse.self, from: data))
}

struct SignalingSetupResponseTests {
    @Test
    func iceServersWithEntries() throws {
        let json = setupResponseJson(iceServers: .array([
            .object(["urls": .array([.string("stun:stun.example.com")])]),
            .object([
                "urls": .array([.string("turn:turn.example.com")]),
                "username": .string("user"),
                "credential": .string("secret")
            ])
        ]))
        let decoded = try decodeBothWays(json)
        for response in [SignalingSetupResponse.fromJson(json), decoded.fromJson, decoded.fromJsonString] {
            #expect(response?.iceServers.map(\.urls) == [["stun:stun.example.com"], ["turn:turn.example.com"]])
            #expect(response?.iceServers.last?.username == "user")
            #expect(response?.iceServers.last?.credential == "secret")
        }
    }

    @Test
    func iceServersEmpty() throws {
        let json = setupResponseJson(iceServers: .array([]))
        let decoded = try decodeBothWays(json)
        for response in [SignalingSetupResponse.fromJson(json), decoded.fromJson, decoded.fromJsonString] {
            #expect(response?.iceServers.count == 0)
        }
    }

    @Test
    func iceServersAbsentIsAnEmptyList() throws {
        let json = setupResponseJson(iceServers: nil)
        let decoded = try decodeBothWays(json)
        for response in [SignalingSetupResponse.fromJson(json), decoded.fromJson, decoded.fromJsonString] {
            #expect(response?.iceServers.count == 0)
        }
    }

    @Test
    func iceServersNullIsAnEmptyList() throws {
        let json = setupResponseJson(iceServers: .null)
        let decoded = try decodeBothWays(json)
        for response in [SignalingSetupResponse.fromJson(json), decoded.fromJson, decoded.fromJsonString] {
            #expect(response?.iceServers.count == 0)
        }
    }

    @Test
    func iceServersOfAWrongTypeIsInvalid() throws {
        let wrongTypes: [JSONValue] = [
            .string("stun:stun.example.com"),
            .number(1),
            .bool(true),
            .object(["urls": .array([.string("stun:stun.example.com")])])
        ]
        for iceServers in wrongTypes {
            let json = setupResponseJson(iceServers: iceServers)
            let decoded = try decodeBothWays(json)
            #expect(SignalingSetupResponse.fromJson(json) == nil, "iceServers: \(iceServers)")
            #expect(decoded.fromJson == nil, "iceServers: \(iceServers)")
            #expect(decoded.fromJsonString == nil, "iceServers: \(iceServers)")
        }
    }

    @Test
    func setupRequestIsNotASetupResponse() throws {
        for json: JSONValue in [
            .object(["type": .string("SETUP_REQUEST")]),
            .object(["type": .string("SETUP_REQUEST"), "iceServers": .null])
        ] {
            let decoded = try decodeDirectly(json)
            #expect(decoded.fromJson == nil, "\(json)")
            #expect(decoded.decodable == nil, "\(json)")
        }
    }

    @Test
    func noTypeAndNoMemberIsInvalid() throws {
        let decoded = try decodeDirectly(.object([:]))
        #expect(decoded.fromJson == nil)
        #expect(decoded.decodable == nil)
    }

    @Test
    func encodingKeepsTheMember() throws {
        let json = SignalingSetupResponse(iceServers: []).toJson()
        #expect(json == setupResponseJson(iceServers: .array([])))
    }
}
