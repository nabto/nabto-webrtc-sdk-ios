import NabtoWebRTC

/**
 * Generalized WebRTC Signaling message to be sent/received by the
 * MessageTransport. This message can contain either a SignalingDescription or a
 * SignalingCandidate.
 */
public struct WebrtcSignalingMessage {
    public var candidate: SignalingCandidate?
    public var description: SignalingDescription?

    /**
     * Construct a WebRTC Signaling message from a SignalingCandidate or a SignalingDescription.
     *
     * A WebrtcSignalingMessage can only contain one of the two, so either the candidate or the description must be nil.
     *
     * @param candidate The candidate if this is a candidate.
     * @param description The description if this is a description.
     */
    public init(candidate: SignalingCandidate? = nil, description: SignalingDescription? = nil) {
        self.candidate = candidate
        self.description = description
    }
}
