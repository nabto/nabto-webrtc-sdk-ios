import NabtoWebRTC

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