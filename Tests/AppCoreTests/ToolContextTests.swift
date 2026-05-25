import AppCore
import SwiftUI
import XCTest

final class ToolContextTests: XCTestCase {
    func testContextInjectsSharedServices() throws {
        let context = ToolContext.testFixture()
        let settings = try context.settingsStore.loadSettings()

        XCTAssertEqual(context.registeredToolCount, 2)
        XCTAssertEqual(settings.outputFolder.url.lastPathComponent, "Inbox")
        XCTAssertTrue(try context.outputInboxStore.listItems().isEmpty)
        XCTAssertTrue(context.jobRunner.listJobs().isEmpty)
    }

    @MainActor
    func testContextCanBePassedToFeatureViewFactory() {
        let context = ToolContext.testFixture()
        let feature = ContextAwareFeature()

        _ = feature.makeView(context: context)

        XCTAssertEqual(feature.metadata.id, "context-aware")
    }
}

private struct ContextAwareFeature: ToolFeature {
    let metadata = ToolMetadata(
        id: "context-aware",
        displayName: "Context Aware",
        shortLabel: "Context",
        systemImage: "gearshape",
        capabilities: [.runsJobs]
    )

    @MainActor
    func makeView(context: ToolContext) -> AnyView {
        AnyView(Text("Registered tools: \(context.registeredToolCount)"))
    }
}

private extension ToolContext {
    static func testFixture() -> ToolContext {
        ToolContext(
            registeredToolCount: 2,
            settingsStore: FixtureSettingsStore(),
            outputInboxStore: FixtureOutputInboxStore(),
            jobRunner: FixtureJobRunner(),
            fileActions: FixtureFileActions(),
            diagnostics: FixtureDiagnostics()
        )
    }
}

private struct FixtureSettingsStore: SettingsStore {
    func loadSettings() throws -> AppSettings {
        AppSettings(outputFolder: StoredFolderLocation(url: URL(fileURLWithPath: "/tmp/Outside Cubase Hub/Inbox")))
    }

    func saveSettings(_ settings: AppSettings) throws {}

    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {}
}

private struct FixtureOutputInboxStore: OutputInboxStore {
    func listItems() throws -> [OutputInboxItem] { [] }
    func addItem(_ item: OutputInboxItem) throws {}
    func updateItem(_ item: OutputInboxItem) throws {}
    func refreshAvailability() throws {}
}

private struct FixtureJobRunner: JobRunning {
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

private struct FixtureFileActions: FileActions {
    @MainActor
    func chooseOutputFolder() -> URL? { nil }

    @MainActor
    func revealInFinder(_ url: URL) {}
}

private struct FixtureDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}
