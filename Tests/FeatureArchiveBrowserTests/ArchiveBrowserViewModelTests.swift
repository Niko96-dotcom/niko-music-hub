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

        let context = TestToolContext.make()

        let viewModel = ArchiveBrowserViewModel(context: context)
        await viewModel.scan()
        XCTAssertFalse(viewModel.songs.isEmpty)
        viewModel.searchQuery = "Neon Hook"
        viewModel.applySearchFilter()
        XCTAssertEqual(viewModel.filteredSongs.count, 1)
        XCTAssertEqual(viewModel.filteredSongs.first?.displayTitle, "Neon Hook")
    }
}
