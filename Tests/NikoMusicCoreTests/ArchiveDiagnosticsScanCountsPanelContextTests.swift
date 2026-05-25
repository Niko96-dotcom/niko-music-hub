import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsScanCountsPanelContextTests: XCTestCase {
    func testPanelSongWarningsValueFormatsCounts() {
        let value = ArchiveDiagnosticsScanCountsPanelContext.panelSongWarningsValue(
            songsWithWarningsCount: 1,
            totalSongWarningCount: 3
        )
        XCTAssertEqual(value, "1 (3 total)")
    }

    func testCountsMatchExportForScanCountLines() {
        let export = """
        songs=7
        songs_with_warnings=1
        total_song_warnings=1
        """
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
            rootPaths: [],
            songCount: 7,
            songsWithWarningsCount: 1,
            totalSongWarningCount: 1,
            globalWarnings: [],
            songWarningSummaries: [],
            skippedEntries: []
        )
        XCTAssertTrue(
            ArchiveDiagnosticsScanCountsPanelContext.countsMatchExport(
                in: export,
                diagnostics: diagnostics
            )
        )
    }

    func testFixtureScanCountsPanelMatchesExporter() throws {
        try CubaseFixtures.ensureGenerated()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [archiveRoot],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let exportText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: home
        )
        XCTAssertEqual(diagnostics.songCount, 7)
        XCTAssertEqual(diagnostics.songsWithWarningsCount, 1)
        XCTAssertEqual(diagnostics.totalSongWarningCount, 1)
        XCTAssertEqual(
            ArchiveDiagnosticsScanCountsPanelContext.panelSongsValue(songCount: diagnostics.songCount),
            "7"
        )
        XCTAssertEqual(
            ArchiveDiagnosticsScanCountsPanelContext.panelSongWarningsValue(
                songsWithWarningsCount: diagnostics.songsWithWarningsCount,
                totalSongWarningCount: diagnostics.totalSongWarningCount
            ),
            "1 (1 total)"
        )
        XCTAssertTrue(
            ArchiveDiagnosticsScanCountsPanelContext.countsMatchExport(
                in: exportText,
                diagnostics: diagnostics
            )
        )
    }
}
