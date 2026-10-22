import Foundation

/// Where one tool run writes, and the guard that admits it, read from one
/// settings snapshot. Unreadable settings refuse the run: they never fall back
/// to defaults, which protect nothing.
public struct ToolOutputDestination: Equatable, Sendable {
    /// The output folder from the snapshot.
    public let folder: URL
    /// The guard from the same snapshot, for APIs that take a guard.
    public let outputGuard: ToolOutputGuard

    /// For callers that already hold the run's snapshot.
    public init(settings: AppSettings) {
        folder = settings.outputFolder.url
        outputGuard = ToolOutputGuard(settings: settings)
    }

    /// One throwing settings read. `loadSettings()` returns defaults when
    /// nothing was ever saved (first run) and throws when saved data is
    /// unreadable; that error is passed on rather than replaced by defaults,
    /// and each tool maps it to its own sentence.
    public static func load(from settingsStore: any SettingsStore) throws -> ToolOutputDestination {
        ToolOutputDestination(settings: try settingsStore.loadSettings())
    }

    /// Admits `folder` or a folder below it (a run's subfolder).
    public func validate(_ folder: URL) throws {
        try outputGuard.validate(folder)
    }
}
