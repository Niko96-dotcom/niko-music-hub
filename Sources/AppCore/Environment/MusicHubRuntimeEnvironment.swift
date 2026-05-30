import Foundation

/// Process-environment flags for tests, smoke, and local dev harnesses.
///
/// Read once at composition or view-model init; do not scatter `ProcessInfo` lookups.
public struct MusicHubRuntimeEnvironment: Sendable, Equatable {
    public static let dryRunOpenKey = "NIKO_MUSIC_HUB_DRY_RUN_OPEN"
    public static let fixtureRootKey = "NIKO_MUSIC_HUB_FIXTURE_ROOT"
    public static let devArchiveRootKey = "NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT"
    public static let settingsSuiteKey = "NIKO_MUSIC_HUB_SETTINGS_SUITE"
    public static let showDevToolKey = "NIKO_MUSIC_HUB_SHOW_DEV_TOOL"
    public static let disableArchiveWatcherKey = "NIKO_MUSIC_HUB_DISABLE_ARCHIVE_WATCHER"
    public static let e2eSmokeKey = "NIKO_MUSIC_HUB_E2E_SMOKE"

    public let dryRunOpen: Bool
    public let fixtureRootURL: URL?
    public let devArchiveRootURL: URL?
    public let usesIsolatedSettingsSuite: Bool
    public let showsDevTool: Bool
    public let disableArchiveWatcher: Bool
    public let e2eSmoke: Bool

    public var usesFixtureRoot: Bool { fixtureRootURL != nil }

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        dryRunOpen = environment[Self.dryRunOpenKey] == "1"
        fixtureRootURL = Self.directoryURL(for: environment[Self.fixtureRootKey])
        devArchiveRootURL = Self.directoryURL(for: environment[Self.devArchiveRootKey])
        usesIsolatedSettingsSuite = environment[Self.settingsSuiteKey] != nil
        showsDevTool = environment[Self.showDevToolKey] == "1"
        disableArchiveWatcher = environment[Self.disableArchiveWatcherKey] == "1"
        e2eSmoke = environment[Self.e2eSmokeKey] == "1"
    }

    /// Snapshot of the process environment at call time (safe for tests that `setenv` before init).
    public static var current: MusicHubRuntimeEnvironment {
        MusicHubRuntimeEnvironment()
    }

    private static func directoryURL(for value: String?) -> URL? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }
}
