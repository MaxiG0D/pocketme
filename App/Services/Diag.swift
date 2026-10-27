import os

/// Temporary tracing for the Mac sidebar click investigation.
enum Diag {
    private static let logger = Logger(subsystem: "com.maxigariepy.pocketme", category: "diag")
    static func log(_ message: String) { logger.notice("\(message, privacy: .public)") }
}
