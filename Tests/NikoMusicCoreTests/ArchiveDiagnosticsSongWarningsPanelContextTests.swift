import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsSongWarningsPanelContextTests: XCTestCase {
    func testPanelLineFormatsTitleAndWarnings() {
        let line = ArchiveDiagnosticsSongWarningsPanelContext.panelLine(
            displayTitle: "Broken Folder Example",
            warnings: ["No CPR project files found"]
        )
        XCTAssertEqual(line, "Broken Folder Example: No CPR project files found")
    }

    func testLineMatchesExportForSongWarningSummary() {
        let export = """
        song=Broken Folder Example
          warning=No CPR project files found
        """
        let summary = SongWarningSummary(
            displayTitle: "Broken Folder Example",
            warnings: ["No CPR project files found"]
        )
        XCTAssertTrue(
            ArchiveDiagnosticsSongWarningsPanelContext.lineMatchesExport(in: export, summary: summary)
        )
    }

    func testFixtureScanSongWarningsPanelMatchesExporter() throws {
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
        let displaySummaries = diagnostics.displaySongWarningSummaries(homeDirectory: home)
        XCTAssertEqual(displaySummaries.count, 1)
        XCTAssertTrue(
            ArchiveDiagnosticsSongWarningsPanelContext.linesMatchExport(
                in: exportText,
                summaries: displaySummaries,
                homeDirectory: home
            )
        )
        XCTAssertEqual(displaySummaries.first?.displayTitle, "Broken Folder Example")
        XCTAssertTrue(displaySummaries.first?.warnings.contains("No CPR project files found") == true)
    }
}
