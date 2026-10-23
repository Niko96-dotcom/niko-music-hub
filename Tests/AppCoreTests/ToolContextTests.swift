import AppCore
import XCTest

final class ToolContextTests: XCTestCase {
    func testContextInjectsSharedServices() throws {
        let context = ToolContext.testFixture()
        let settings = try context.settingsStore.loadSettings()

        XCTAssertEqual(settings.outputFolder.url.lastPathComponent, "Inbox")
        XCTAssertTrue(try context.outputInboxStore.listItems().isEmpty)
        XCTAssertTrue(context.jobRunner.listJobs().isEmpty)
    }

    /// The archive view model needs a context before the feature list and the
    /// registry exist. Launch warnings, which a registry failure adds to, go to
    /// their only reader, the shell, so one context serves the whole launch.
    func testCompositionBuildsOneContextAndHandsLaunchWarningsToTheShell() throws {
        let composition = SourceLex.stripped(try SourceTestSupport.read("Sources/NikoMusicHub/AppComposition.swift"))
        XCTAssertEqual(composition.components(separatedBy: "ToolContext(").count - 1, 1)
        XCTAssertTrue(composition.contains("persistenceIssues: persistenceIssues"))

        let shell = SourceLex.stripped(try SourceTestSupport.read("Sources/NikoMusicHub/AppShell/AppShellView.swift"))
        XCTAssertTrue(shell.contains("persistenceIssues: [PersistenceIssue]"))
        XCTAssertFalse(shell.contains("context.persistenceIssues"))
    }

    func testAppShellUsesInjectedPreferencesInsteadOfAppStorage() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/AppShell/AppShellView.swift",
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("@AppStorage"))
        XCTAssertTrue(source.contains("shellSession"))
        XCTAssertTrue(source.contains("HubShellSession"))

        let session = try String(
            contentsOfFile: "Sources/AppCore/Shell/HubShellSession.swift",
            encoding: .utf8
        )
        XCTAssertTrue(session.contains("preferences.bool"))
        XCTAssertTrue(session.contains("preferences.set"))
        XCTAssertTrue(session.contains("hub.shell.panels.toolsVisible"))
        XCTAssertTrue(session.contains("hub.shell.panels.inboxVisible"))
        XCTAssertFalse(session.contains("@AppStorage"))
    }

    func testAppCompositionCapturesSQLiteStartupIssues() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/AppComposition.swift",
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("try? SQLiteArchiveIndexStore"))
        XCTAssertFalse(source.contains("try? SQLiteSongUserMetadataStore"))
        XCTAssertFalse(source.contains("try? SQLiteCollaboratorStore"))
        XCTAssertTrue(source.contains("persistenceIssues"))
        XCTAssertTrue(source.contains("makeSQLiteStore"))
        XCTAssertFalse(source.contains("try! ToolRegistry"))
    }

    func testAppCompositionDoesNotEraseIsolatedSettingsOnLaunch() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/AppComposition.swift",
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("removePersistentDomain(forName: suiteName)"))
    }

    func testArchiveSmokeUsesIsolatedPreferences() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/ArchiveSmokeCommands.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("makeSmokeUserDefaults"))
        XCTAssertTrue(source.contains("UserDefaultsSettingsStore(userDefaults: smokeDefaults)"))
        XCTAssertTrue(source.contains("UserDefaultsPreferenceStore(userDefaults: smokeDefaults)"))
    }
}

private extension ToolContext {
    static func testFixture() -> ToolContext {
        ToolContext(
            settingsStore: FixtureSettingsStore(),
            preferences: InMemoryPreferenceStore(),
            outputInboxStore: FixtureOutputInboxStore(),
            jobRunner: FixtureJobRunner(),
            fileActions: FixtureFileActions(),
            diagnostics: FixtureDiagnostics()
        )
    }
}

private struct FixtureSettingsStore: SettingsStore {
    func loadSettings() throws -> AppSettings {
        AppSettings(outputFolder: StoredFolderLocation(url: URL(fileURLWithPath: "/tmp/Niko Music Hub/Inbox")))
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
    func chooseDirectory(prompt: String) -> URL? { nil }

    @MainActor
    func chooseExecutable(prompt: String) -> URL? { nil }

    @MainActor
    func chooseAudioFile(prompt: String) -> URL? { nil }

    @MainActor
    func revealInFinder(_ url: URL) {}
}

private struct FixtureDiagnostics: Diagnostics {
    func log(_ level: DiagnosticLevel, _ message: String) {}
}
