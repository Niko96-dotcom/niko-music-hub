import Foundation
import NikoMusicCore
import OSLog

/// Per-feature unified-logging categories. Subsystem is always the app bundle
/// id (`Bundle.main.bundleIdentifier ?? "NikoMusicHub"`); the category keeps
/// `log stream --predicate 'subsystem == ... && category == ...'` filtering cheap.
public enum DiagnosticsCategory: String, Sendable, CaseIterable {
    case vault = "Vault"
    case archive = "Archive"
    case downloader = "Downloader"
    case recorder = "Recorder"
    case stemSeparation = "StemSeparation"
    case converter = "Converter"
    case updates = "Updates"
    case windowing = "Windowing"
    case commands = "Commands"
    case jobs = "Jobs"
    case general = "General"
}

/// Shared subsystem so every feature filters under one predicate.
public enum HubLogging {
    public static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "NikoMusicHub"
    }

    public static func logger(category: DiagnosticsCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    public static func logger(categoryName: String) -> Logger {
        Logger(subsystem: subsystem, category: categoryName)
    }
}

/// Unified-logging `Diagnostics` for the shipped app target.
/// Tests and CLI tools keep `ConsoleDiagnostics` / `CapturingDiagnostics`.
public struct OSLogDiagnostics: Diagnostics {
    private let logger: Logger
    public let category: DiagnosticsCategory

    public init(category: DiagnosticsCategory = .general) {
        self.category = category
        self.logger = HubLogging.logger(category: category)
    }

    public init(categoryName: String) {
        // For one-off categories; maps back to .general when the name matches a
        // known case so `category` stays meaningful.
        if let known = DiagnosticsCategory(rawValue: categoryName) {
            self.category = known
            self.logger = HubLogging.logger(category: known)
        } else {
            self.category = .general
            self.logger = HubLogging.logger(categoryName: categoryName)
        }
    }

    /// Returns a diagnostics scoped to another category (same subsystem).
    public func scoped(to category: DiagnosticsCategory) -> OSLogDiagnostics {
        OSLogDiagnostics(category: category)
    }

    public func log(_ level: DiagnosticLevel, _ message: String) {
        // Free-form messages may embed absolute paths, song titles, or error
        // text. Redact home-prefixed paths and keep the whole line private;
        // call sites that need a public ID use a direct Logger with
        // `privacy: .public` for that single interpolation instead.
        let redacted = DiagnosticsPathRedactor.redactPathsInText(message)
        switch level {
        case .debug:
            logger.debug("\(redacted, privacy: .private)")
        case .info:
            logger.info("\(redacted, privacy: .private)")
        case .warning:
            logger.notice("\(redacted, privacy: .private)")
        case .error:
            logger.error("\(redacted, privacy: .private)")
        }
    }
}

public extension Diagnostics {
    /// Minimal per-feature scoping without changing the protocol: when the
    /// underlying value is `OSLogDiagnostics`, returns a logger for the
    /// requested category; otherwise returns `self` (console/capturing).
    func scoped(to category: DiagnosticsCategory) -> any Diagnostics {
        if let oslog = self as? OSLogDiagnostics {
            return oslog.scoped(to: category)
        }
        return self
    }
}
