import OSLog

internal struct Log {
    private static var subsystem = Bundle.main.bundleIdentifier!

    static let signalingClient = CustomLogger(subsystem: subsystem, category: "SignalingClient")
    static let webSocket = CustomLogger(subsystem: subsystem, category: "WebSocketConnection")
    static let reliability = CustomLogger(subsystem: subsystem, category: "Reliability")
}

internal class CustomLogger {
    let log: OSLog

    init(subsystem: String, category: String) {
        log = OSLog(subsystem: subsystem, category: category)
    }

    func trace(_ message: String) {
        os_log(.debug, log: self.log, "%@", message)
    }

    func debug(_ message: String) {
        os_log(.debug, log: self.log, "%@", message)
    }

    func info(_ message: String) {
        os_log(.info, log: self.log, "%@", message)
    }

    func notice(_ message: String) {
        os_log(.default, log: self.log, "%@", message)
    }

    func warning(_ message: String) {
        os_log(.error, log: self.log, "%@", message)
    }

    func error(_ message: String) {
        os_log(.error, log: self.log, "%@", message)
    }

    func critical(_ message: String) {
        os_log(.fault, log: self.log, "%@", message)
    }

    func fault(_ message: String) {
        os_log(.fault, log: self.log, "%@", message)
    }
}
