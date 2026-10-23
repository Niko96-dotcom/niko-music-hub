import AppCore
@testable import FeatureArchiveBrowser
import Foundation

enum TestToolContext {
    static func make() -> ToolContext {
        make(
            settingsStore: UserDefaultsSettingsStore(
                userDefaults: UserDefaults(suiteName: "FeatureArchiveBrowserTests.\(UUID())")!,
                key: "settings"
            )
        )
    }

    static func make(
        settingsStore: SettingsStore,
        fileActions: (any FileActions)? = nil,
        diagnostics: CapturingDiagnostics = CapturingDiagnostics()
    ) -> ToolContext {
        ToolContext(
            settingsStore: settingsStore,
            preferences: InMemoryPreferenceStore(),
            outputInboxStore: JSONOutputInboxStore(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("inbox-\(UUID()).json")
            ),
            jobRunner: JobRunner(),
            fileActions: fileActions ?? NoopTestFileActions(),
            diagnostics: diagnostics
        )
    }

    static func make(fileActions: any FileActions) -> ToolContext {
        make(settingsStore: UserDefaultsSettingsStore(
            userDefaults: UserDefaults(suiteName: "FeatureArchiveBrowserTests.\(UUID())")!,
            key: "settings"
        ), fileActions: fileActions)
    }
}

final class RevealedURLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func append(_ url: URL) {
        lock.lock()
        stored.append(url)
        lock.unlock()
    }
}

struct CapturingTestFileActions: FileActions {
    let revealed: RevealedURLBox

    func chooseOutputFolder() -> URL? { nil }
    func chooseDirectory(prompt: String) -> URL? { nil }
    func chooseExecutable(prompt: String) -> URL? { nil }
    func chooseAudioFile(prompt: String) -> URL? { nil }
    func revealInFinder(_ url: URL) {
        revealed.append(url)
    }
}

private struct NoopTestFileActions: FileActions {
    func chooseOutputFolder() -> URL? { nil }
    func chooseDirectory(prompt: String) -> URL? { nil }
    func chooseExecutable(prompt: String) -> URL? { nil }
    func chooseAudioFile(prompt: String) -> URL? { nil }
    func revealInFinder(_ url: URL) {}
}

extension ArchiveBrowserViewModel {
    /// What Settings > Music archive > Remove does: edit the stored scan list.
    /// The archive answers the save's publish with `followStoredSettings()`;
    /// tests run that reaction at once instead of waiting a main-queue turn.
    func removeFolderAsSettingsDoes(_ folder: URL) throws {
        try settingsStore.updateSettings { $0 = ArchiveScanList().removing(folder, from: $0) }
        followStoredSettings()
    }
}
