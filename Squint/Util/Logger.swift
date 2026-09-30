import Foundation
import os

struct AppLogger {
    static let shared = AppLogger()
    private let logger = Logger(subsystem: "com.zsolttanko.squint", category: "app")

    func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    func error(_ message: String) { logger.error("\(message, privacy: .public)") }
    func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
}
