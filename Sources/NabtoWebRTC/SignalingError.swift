import Foundation

/**
 * Error codes that can be contained in a SignalingError
 */
public enum SignalingErrorCode {
    case decodeError
    case verificationError
    case channelClosed
    case channelNotFound
    case noMoreChannels
    case unknown(String)

    public var stringValue: String {
        switch self {
            case .decodeError: return "DECODE_ERROR"
            case .verificationError: return "VERIFICATION_ERROR"
            case .channelClosed: return "CHANNEL_CLOSED"
            case .channelNotFound: return "CHANNEL_NOT_FOUND"
            case .noMoreChannels: return "NO_MORE_CHANNELS"
            case .unknown(let code): return code
        }
    }

    public static func from(string str: String) -> SignalingErrorCode {
        switch str {
            case "DECODE_ERROR": .decodeError
            case "VERIFICATION_ERROR": .verificationError
            case "CHANNEL_CLOSED": .channelClosed
            case "CHANNEL_NOT_FOUND": .channelNotFound
            case "NO_MORE_CHANNELS": .noMoreChannels
            default: .unknown(str)
        }
    }
}

/**
 * SignalingError represents errors that are received from or sent to the device peer.
 */
public struct SignalingError: LocalizedError {
    private(set) var errorCode: SignalingErrorCode
    private(set) var errorMessage: String
    private(set) var isRemote: Bool
    public var errorDescription: String? { return self.errorMessage }
    
    public init(errorCode: SignalingErrorCode, errorMessage: String, isRemote: Bool = false) {
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.isRemote = isRemote
    }
}
