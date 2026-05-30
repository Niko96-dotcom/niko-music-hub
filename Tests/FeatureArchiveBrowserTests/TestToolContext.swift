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

    static func make(settingsStore: SettingsStore) -> ToolContext {
        ToolContext(
            registeredToolCount: 1,
            settingsStore: settingsStore,
            outputInboxStore: JSONOutputInboxStore(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("inbox-\(UUID()).json")
            ),
            jobRunner: JobRunner(),
            fileActions: NoopTestFileActions(),
            diagnostics: CapturingDiagnostics()
        )
    }
}

private struct NoopTestFileActions: FileActions {
    func chooseOutputFolder() -> URL? { nil }
    func chooseDirectory(prompt: String) -> URL? { nil }
    func chooseExecutable(prompt: String) -> URL? { nil }
    func revealInFinder(_ url: URL) {}
}
