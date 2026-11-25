import Foundation
import Testing
@testable import NabtoWebRTC
@testable import NabtoWebRTCUtil

private func candidateJson(sdpMLineIndex: JSONValue?) -> JSONValue {
    var candidate: [String: JSONValue] = ["candidate": .string("candidate:1 1 udp 1 192.0.2.1 9 typ host")]
    if let sdpMLineIndex = sdpMLineIndex {
        candidate["sdpMLineIndex"] = sdpMLineIndex
    }
    return .object(["type": .string("CANDIDATE"), "candidate": .object(candidate)])
}

struct SignalingCandidateTests {
    @Test
    func integerIndexDecodes() {
        #expect(SignalingCandidate.fromJson(candidateJson(sdpMLineIndex: .number(2)))?.candidate.sdpMLineIndex == 2)
    }

    @Test
    func absentIndexDecodesAsBefore() {
        #expect(SignalingCandidate.fromJson(candidateJson(sdpMLineIndex: nil))?.candidate.sdpMLineIndex == 0)
    }

    @Test
    func indexOutsideIntOrNotAnIntegerIsInvalid() {
        for index in [1e300, -1e300, 1.5] {
            #expect(SignalingCandidate.fromJson(candidateJson(sdpMLineIndex: .number(index))) == nil, "\(index)")
        }
    }
}
