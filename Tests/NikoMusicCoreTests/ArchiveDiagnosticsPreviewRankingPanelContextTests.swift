import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsPreviewRankingPanelContextTests: XCTestCase {
    func testTiebreakLegendDocumentsRankingOrder() {
        let legend = ArchiveDiagnosticsPreviewRankingPanelContext.tiebreakLegend
        XCTAssertTrue(legend.contains("role"))
        XCTAssertTrue(legend.contains("version"))
        XCTAssertTrue(legend.contains("duration"))
    }

    func testScanSummaryCountsTooShortNonMainPreviewsInFixtures() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let context = ArchiveDiagnosticsPreviewRankingPanelContext.from(songs: result.songs)

        XCTAssertGreaterThanOrEqual(context.tooShortNonMainPreviewCount, 1)
        XCTAssertGreaterThanOrEqual(context.songsWithTooShortNonMainPreviews, 1)
        XCTAssertNotNil(context.scanHeaderCallout)
        XCTAssertTrue(context.scanHeaderCallout?.contains("too short") == true)
    }

    func testSelectedSongHeaderForRankingLab() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let lab = try XCTUnwrap(result.songs.first { $0.displayTitle == "Preview Ranking Lab" })
        let header = ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(for: lab)

        XCTAssertNotNil(header)
        XCTAssertTrue(header?.contains("Lab Song v3 mix.wav") == true)
        XCTAssertTrue(header?.contains("too short") == true)
    }

    func testSelectedSongHeaderNilWhenNoSong() {
        XCTAssertNil(ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongHeader(for: nil))
    }

    func testPerSongTooShortBreakdownForRankingLabFixture() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let context = ArchiveDiagnosticsPreviewRankingPanelContext.from(songs: result.songs)

        let labBreakdown = try XCTUnwrap(
            context.tooShortSongBreakdowns.first { $0.displayTitle == "Preview Ranking Lab" }
        )
        XCTAssertEqual(labBreakdown.clipCount, 1)
        XCTAssertEqual(labBreakdown.clipNames, ["Lab Song short clip.wav"])
    }
}
