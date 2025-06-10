import OSLog

internal struct Log {
    private static var subsystem = Bundle.main.bundleIdentifier!

    static let signalingClient = Logger(subsystem: subsystem, category: "SignalingClient")
    static let webSocket = Logger(subsystem: subsystem, category: "WebSocketConnection")
    static let reliability = Logger(subsystem: subsystem, category: "Reliability")
}
