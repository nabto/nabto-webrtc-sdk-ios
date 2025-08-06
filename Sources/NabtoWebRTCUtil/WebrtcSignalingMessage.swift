import NabtoWebRTC

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
