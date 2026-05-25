import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsPanelContextTests: XCTestCase {
    func testFixtureScanSupportSummaryMatchesExportSummaryLine() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let roots = [CubaseFixtures.archiveRoot]
        let result = try scanner.scan(roots: roots)
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: roots,
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let panel = ArchiveDiagnosticsPanelContext.from(diagnostics, homeDirectory: home)
        let exportLine = diagnostics.exportSummaryLine(homeDirectory: home)

        XCTAssertEqual(panel.supportSummaryLine, exportLine)
        XCTAssertTrue(panel.supportSummaryLine.hasPrefix("roots:"))
        XCTAssertTrue(panel.supportSummaryLine.contains("Scanned 5 songs"))
        XCTAssertTrue(panel.supportSummaryLine.contains("1 song(s) with"))
        XCTAssertTrue(panel.supportSummaryLine.contains("2 skipped at roots"))
    }

    func testSupportSummaryUsesRedactedRoots() {
        let home = "/Users/tester"
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["\(home)/Music/Cubase"],
            songCount: 3,
            songsWithWarningsCount: 0,
            totalSongWarningCount: 0,
            globalWarnings: [],
            songWarningSummaries: [],
            skippedEntries: []
        )

        let panel = ArchiveDiagnosticsPanelContext.from(diagnostics, homeDirectory: home)
        XCTAssertEqual(
            panel.supportSummaryLine,
            "roots: ~/Music/Cubase · Scanned 3 songs · no warnings · nothing skipped at roots"
        )
    }
}
