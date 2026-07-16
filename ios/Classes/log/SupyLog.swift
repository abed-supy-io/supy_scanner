import Foundation
import os.log

/// Thin tagged wrapper around `os.Logger` used by every native diagnostic
/// site inside the plugin. Mirror of the Dart `SupyLog` facade
/// (`lib/src/log/supy_log.dart`). Keep the level enum and tag convention in
/// sync.
///
/// Host apps that want to silence the library entirely flip `enabled` to
/// `false` (e.g. from a debug menu).
///
/// Never log barcode payloads, OCR text, or file URIs through this — see
/// `docs/SECURITY.md` §8.
@objc public final class SupyLog: NSObject {
    /// Toggle the entire native log stream.
    @objc public static var enabled: Bool = true

    private static let subsystem = "io.supy.scanner"
    private static let defaultLogger = Logger(subsystem: subsystem, category: "SupyScanner")
    private static var loggers: [String: Logger] = [:]
    private static let lock = NSLock()

    private static func logger(for tag: String) -> Logger {
        if tag.isEmpty {
            return defaultLogger
        }
        lock.lock()
        defer { lock.unlock() }
        if let cached = loggers[tag] {
            return cached
        }
        let fresh = Logger(subsystem: subsystem, category: tag)
        loggers[tag] = fresh
        return fresh
    }

    @objc public static func d(_ message: String, tag: String = "SupyScanner") {
        guard enabled else { return }
        logger(for: tag).debug("\(message, privacy: .public)")
    }

    @objc public static func i(_ message: String, tag: String = "SupyScanner") {
        guard enabled else { return }
        logger(for: tag).info("\(message, privacy: .public)")
    }

    @objc public static func w(_ message: String, tag: String = "SupyScanner") {
        guard enabled else { return }
        logger(for: tag).warning("\(message, privacy: .public)")
    }

    @objc public static func e(_ message: String, tag: String = "SupyScanner") {
        guard enabled else { return }
        logger(for: tag).error("\(message, privacy: .public)")
    }
}
