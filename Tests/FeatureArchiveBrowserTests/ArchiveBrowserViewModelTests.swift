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
        let songID = try XCTUnwrap(viewModel.filteredSongs.first?.id)
        XCTAssertFalse(viewModel.searchMatchSummaries[songID, default: ""].isEmpty)
    }

    func testScanExposesDiagnosticsSummary() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()

        let diagnostics = try XCTUnwrap(viewModel.scanDiagnostics)
        XCTAssertEqual(diagnostics.songCount, 4)
        XCTAssertEqual(diagnostics.songsWithWarningsCount, 1)
        XCTAssertTrue(
            diagnostics.skippedEntries.contains { $0.kind == .nonFolderAtRoot }
        )
        XCTAssertFalse(diagnostics.summaryLine.isEmpty)
        XCTAssertFalse(diagnostics.displayRootPaths().isEmpty)
        XCTAssertTrue(
            diagnostics.displayRootPaths().first?.contains("CubaseArchive") == true
                || diagnostics.displayRootPaths().first?.hasPrefix("~") == true
        )
    }

    func testScanExposesPreviewRankingSummaryForLab() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()

        let lab = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Preview Ranking Lab" })
        let summary = try XCTUnwrap(PreviewRankingExplainability.mainPreviewSummary(for: lab))
        XCTAssertTrue(summary.contains("v3"))
        XCTAssertTrue(summary.contains("wav"))
    }

    func testExportDiagnosticsIncludesSelectedSongPreviewRanking() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        let lab = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Preview Ranking Lab" })
        viewModel.selectSong(lab)

        try viewModel.exportDiagnostics()
        let exportPath = try XCTUnwrap(viewModel.lastDiagnosticsExportPath)
        let text = try String(contentsOf: URL(fileURLWithPath: exportPath), encoding: .utf8)
        XCTAssertTrue(text.contains("selected_song_title=Preview Ranking Lab"))
        XCTAssertTrue(text.contains("main_preview_summary="))
        XCTAssertTrue(text.contains("v3"))
        XCTAssertTrue(text.contains("preview_rank_line="))
    }

    func testExportDiagnosticsIncludesActiveSearchContext() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        defer { unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT") }

        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        await viewModel.scan()
        viewModel.searchQuery = "neon hk"
        viewModel.applySearchFilter()
        XCTAssertEqual(viewModel.filteredSongs.count, 1)

        try viewModel.exportDiagnostics()
        let exportPath = try XCTUnwrap(viewModel.lastDiagnosticsExportPath)
        let text = try String(contentsOf: URL(fileURLWithPath: exportPath), encoding: .utf8)
        XCTAssertTrue(text.contains("search_query=neon hk"))
        XCTAssertTrue(text.contains("search_match title=Neon Hook"))
        XCTAssertTrue(text.contains("summary="))
    }
}
