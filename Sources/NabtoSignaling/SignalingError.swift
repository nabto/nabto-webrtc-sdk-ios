import Foundation

public enum SignalingErrorCode: String {
    case decodeError = "DECODE_ERROR"
    case verificationError = "VERIFICATION_ERROR"
    case channelClosed = "CHANNEL_CLOSED"
    case channelNotFound = "CHANNEL_NOT_FOUND"
    case noMoreChannels = "NO_MORE_CHANNELS"
}

public struct SignalingError: LocalizedError {
    private(set) var errorCode: SignalingErrorCode
    private(set) var errorMessage: String
    private(set) var isRemote: Bool
    public var errorDescription: String? { return self.errorMessage }

    init(errorCode: SignalingErrorCode, errorMessage: String, isRemote: Bool = false) {
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.isRemote = isRemote
    }
}
