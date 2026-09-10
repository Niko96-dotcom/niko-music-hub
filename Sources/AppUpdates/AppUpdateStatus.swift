import Foundation

/// The updater state the app surfaces in its own UI.
///
/// Sparkle draws its own progress and confirmation windows; this mirror exists
/// so Settings and the menu can describe what is happening without guessing.
public enum AppUpdateStatus: Equatable, Sendable {
    /// No check has run yet in this launch.
    case idle
    /// Contacting the feed.
    case checking
    /// The feed offered a newer build and Sparkle is asking the user about it.
    case updateAvailable(version: String)
    /// Downloading the enclosure. Sparkle's own window owns the progress bar;
    /// the standard user driver exposes no byte counts to mirror here.
    case downloading(version: String)
    /// Verifying and unpacking the downloaded enclosure.
    case extracting(version: String)
    /// Staged and waiting for the relaunch.
    case readyToRelaunch(version: String)
    /// The feed had nothing newer. This is a healthy outcome, not a failure.
    case upToDate(checkedAt: Date)
    /// A check ran and genuinely failed.
    case failed(message: String)
    /// The build cannot check at all; see `AppUpdateConfigurationError`.
    case unavailable(reason: String)

    /// True while a session owns the updater and a new check must not start.
    public var isBusy: Bool {
        switch self {
        case .checking, .updateAvailable, .downloading, .extracting, .readyToRelaunch:
            return true
        case .idle, .upToDate, .failed, .unavailable:
            return false
        }
    }

    /// A permanently disabled updater never offers a retry.
    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    /// Short line for Settings and the menu.
    public var summary: String {
        switch self {
        case .idle:
            return "Not checked yet"
        case .checking:
            return "Checking for updates…"
        case .updateAvailable(let version):
            return "Version \(version) is available"
        case .downloading(let version):
            return "Downloading version \(version)…"
        case .extracting(let version):
            return "Preparing version \(version)…"
        case .readyToRelaunch(let version):
            return "Version \(version) is ready — relaunch to finish"
        case .upToDate(let checkedAt):
            return "Up to date — checked \(Self.timeFormatter.string(from: checkedAt))"
        case .failed(let message):
            return message
        case .unavailable(let reason):
            return reason
        }
    }

    /// Only genuine failures are worth styling as a warning; `upToDate` is not one.
    public var isProblem: Bool {
        switch self {
        case .failed, .unavailable:
            return true
        case .idle, .checking, .updateAvailable, .downloading, .extracting, .readyToRelaunch, .upToDate:
            return false
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
