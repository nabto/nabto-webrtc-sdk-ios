import NabtoWebRTC

public struct WebrtcSignalingMessage {
    public var candidate: SignalingCandidate?
    public var description: SignalingDescription?

    public init(candidate: SignalingCandidate? = nil, description: SignalingDescription? = nil) {
        self.candidate = candidate
        self.description = description
    }
}
