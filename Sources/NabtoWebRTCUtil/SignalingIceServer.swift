import NabtoWebRTC

/**
 * Struct representing an ICE server returned by the Nabto Backend.
 */
public struct SignalingIceServer: Codable, SignalingMessage {
    /**
     * List of URLs for the ICE server. If the server is a TURN server, the
     * credentials will be valid for all URLs in the list.
     */
    public var urls: [String]

    /**
     * credential will not exist if the server is a STUN server, and a
     * credential string if it is a TURN server.
     */
    public var credential: String?

    /**
     * username will be not exist if the server is a STUN server, and a
     * username if it is a TURN server.
     */
    public var username: String?

    /**
     * Initialize an ICE server object.
     *
     * @param urls List of URLs for this ICE server.
     * @param credential Credential if this is a TURN server.
     * @param username Username if this is a TURN server.
     */
    public init(
        urls: [String],
        credential: String? = nil,
        username: String? = nil
    ) {
        self.urls = urls
        self.credential = credential
        self.username = username
    }

    /**
     * Convert the ICE server to JSON.
     *
     * @return The resulting JSON object.
     */
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

    /**
     * Build an ICE server from a JSON string.
     *
     * @param json The JSON string to parse.
     * @return The created ICE server object.
     */
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
