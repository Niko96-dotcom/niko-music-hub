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

    func testScanHeaderCalloutMatchesExporterLine() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [CubaseFixtures.archiveRoot]
        )
        let callout = try XCTUnwrap(diagnostics.previewRankingPanel.scanHeaderCallout)
        let exportText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: nil
        )
        XCTAssertTrue(exportText.contains("preview_ranking_scan_callout=\(callout)"))
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

    func testDurationTiebreakFixtureExposesSelectedSongPreviewTiebreakCallout() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let lab = try XCTUnwrap(result.songs.first { $0.displayTitle == "Equal Score Duration Tiebreak" })
        let callout = try XCTUnwrap(
            ArchiveDiagnosticsPreviewRankingPanelContext.selectedSongPreviewTiebreakCallout(for: lab)
        )
        XCTAssertTrue(callout.contains("Equal score — longer preview"))
    }

    func testTooShortBreakdownPanelDisplayLine() {
        let breakdown = TooShortNonMainSongBreakdown(
            displayTitle: "Preview Ranking Lab",
            clipCount: 1,
            clipNames: ["Lab Song short clip.wav"]
        )
        XCTAssertEqual(
            breakdown.panelDisplayLine,
            "Preview Ranking Lab: 1 too short clip — Lab Song short clip.wav"
        )
    }
}
