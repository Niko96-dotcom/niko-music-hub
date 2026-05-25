import AppCore
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

@MainActor
final class ArchiveBrowserViewModelTests: XCTestCase {
    func testScanFixtureRootFindsNeonHook() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let context = ToolContext(
            registeredToolCount: 1,
            settingsStore: UserDefaultsSettingsStore(
                userDefaults: UserDefaults(suiteName: "ArchiveBrowserViewModelTests.\(UUID())")!,
                key: "settings"
            ),
            outputInboxStore: JSONOutputInboxStore(
                storageURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("inbox-\(UUID()).json")
            ),
            jobRunner: JobRunner(),
            fileActions: NoopFileActions(),
            diagnostics: ConsoleDiagnostics()
        )

        let viewModel = ArchiveBrowserViewModel(context: context)
        await viewModel.scan()
        XCTAssertFalse(viewModel.songs.isEmpty)
        viewModel.searchQuery = "Neon Hook"
        viewModel.applySearchFilter()
        XCTAssertEqual(viewModel.filteredSongs.count, 1)
        XCTAssertEqual(viewModel.filteredSongs.first?.displayTitle, "Neon Hook")
    }
}

private struct NoopFileActions: FileActions {
    func chooseOutputFolder() -> URL? { nil }
    func revealInFinder(_ url: URL) {}
}
