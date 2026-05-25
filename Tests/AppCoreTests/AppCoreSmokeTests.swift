import AppCore
import SwiftUI
import XCTest

final class AppCoreSmokeTests: XCTestCase {
    func testRegistryExposesFeatureMetadataInOrder() throws {
        let first = SmokeFeature(id: "first", shortLabel: "First")
        let second = SmokeFeature(id: "second", shortLabel: "Second")

        let registry = try ToolRegistry(features: [first, second])

        XCTAssertEqual(registry.metadata.map(\.shortLabel), ["First", "Second"])
    }

    func testRegistryKeepsFirstFeatureForLaunch() throws {
        let first = SmokeFeature(id: "first", shortLabel: "First")
        let second = SmokeFeature(id: "second", shortLabel: "Second")

        let registry = try ToolRegistry(features: [first, second])

        XCTAssertEqual(registry.firstFeatureID, "first")
    }
}

private struct SmokeFeature: ToolFeature {
    let metadata: ToolMetadata

    init(id: ToolFeatureID, shortLabel: String) {
        metadata = ToolMetadata(
            id: id,
            displayName: shortLabel,
            shortLabel: shortLabel,
            systemImage: "wrench.and.screwdriver"
        )
    }

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(EmptyView())
    }
}

extension ToolContext {
    static func smokeTest(registeredToolCount: Int = 1) -> ToolContext {
        ToolContext(
            registeredToolCount: registeredToolCount,
            settingsStore: SmokeSettingsStore(),
            outputInboxStore: SmokeOutputInboxStore(),
            jobRunner: SmokeJobRunner(),
            fileActions: SmokeFileActions(),
            diagnostics: SmokeDiagnostics()
        )
    }
}

private struct SmokeSettingsStore: SettingsStore {
    func loadSettings() throws -> AppSettings { .default }
    func saveSettings(_ settings: AppSettings) throws {}
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {}
}

private struct SmokeOutputInboxStore: OutputInboxStore {
    func listItems() throws -> [OutputInboxItem] { [] }
    func addItem(_ item: OutputInboxItem) throws {}
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private struct SmokeJobRunner: JobRunning {
    func listJobs() -> [Job] { [] }
    func job(id: Job.ID) -> Job? { nil }
    func enqueue(
        title: String,
        sourceToolID: ToolFeatureID,
        operation: @escaping @Sendable (JobProgress) async throws -> Void
    ) -> Job {
        Job(sourceToolID: sourceToolID, title: title)
    }
    func cancelJob(id: Job.ID) {}
}

private struct SmokeFileActions: FileActions {
    @MainActor
    func chooseOutputFolder() -> URL? { nil }

    @MainActor
    func revealInFinder(_ url: URL) {}
}

private struct SmokeDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}
