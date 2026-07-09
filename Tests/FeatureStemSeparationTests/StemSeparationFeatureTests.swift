import AppCore
@testable import FeatureStemSeparation
import Foundation
import Testing

struct StemSeparationFeatureTests {

    @Test
    func metadata_matchesExpectations() {
        let feature = StemSeparationFeature()
        #expect(feature.metadata.id == "stem-separation")
        #expect(feature.metadata.displayName == "Stem Separation")
        #expect(feature.metadata.shortLabel == "Stems")
        #expect(feature.metadata.capabilities.contains(.producesFiles))
        #expect(feature.metadata.capabilities.contains(.runsJobs))
    }

    @Test
    @MainActor
    func makeView_reusesSessionViewModelAcrossCalls() {
        let feature = StemSeparationFeature()
        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: FeatureTestSettingsStore(),
            outputInboxStore: FeatureTestOutputInboxStore(),
            jobRunner: JobRunner(),
            fileActions: FeatureTestFileActions(),
            diagnostics: FeatureTestDiagnostics()
        )

        _ = feature.makeView(context: context)
        let first = feature.sessionViewModelForTesting
        _ = feature.makeView(context: context)
        let second = feature.sessionViewModelForTesting

        #expect(first != nil)
        #expect(first === second)
    }
}

private final class FeatureTestSettingsStore: SettingsStore, @unchecked Sendable {
    var stored: AppSettings = .default
    func loadSettings() throws -> AppSettings { stored }
    func saveSettings(_ settings: AppSettings) throws { stored = settings }
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        var settings = stored
        update(&settings)
        stored = settings
    }
}

private final class FeatureTestOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    func listItems() throws -> [OutputInboxItem] { [] }
    func addItem(_ item: OutputInboxItem) throws {}
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private struct FeatureTestFileActions: FileActions {
    @MainActor func chooseOutputFolder() -> URL? { nil }
    @MainActor func chooseDirectory(prompt: String) -> URL? { nil }
    @MainActor func chooseExecutable(prompt: String) -> URL? { nil }
    @MainActor func chooseAudioFile(prompt: String) -> URL? { nil }
    @MainActor func revealInFinder(_ url: URL) {}
}

private struct FeatureTestDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}
