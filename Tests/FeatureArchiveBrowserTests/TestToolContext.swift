import AppCore
@testable import FeatureArchiveBrowser
import Foundation

enum TestToolContext {
    static func make() -> ToolContext {
        ToolContext(
            registeredToolCount: 1,
            settingsStore: UserDefaultsSettingsStore(
                userDefaults: UserDefaults(suiteName: "FeatureArchiveBrowserTests.\(UUID())")!,
                key: "settings"
            ),
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
    func revealInFinder(_ url: URL) {}
}
