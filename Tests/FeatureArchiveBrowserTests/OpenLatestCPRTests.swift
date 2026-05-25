import AppCore
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

@MainActor
final class OpenLatestCPRTests: XCTestCase {
    func testDryRunOpenLogsNeonHookCPR() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        setenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN", "1", 1)
        defer {
            unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
            unsetenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN")
        }

        let context = TestToolContext.make()

        let viewModel = ArchiveBrowserViewModel(context: context)
        await viewModel.scan()

        let neon = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Neon Hook" })
        try viewModel.openLatestCPR(for: neon)
        let path = try XCTUnwrap(viewModel.lastDryRunLog)
        XCTAssertTrue(path.contains("Neon Hook"))
        XCTAssertTrue(path.hasSuffix(".cpr"))
    }
}
