import XCTest
@testable import NikoMusicCore

final class ArchiveScanDiagnosticsTests: XCTestCase {
    func testDisplayRootPathsRedactsHomePrefix() {
        let home = "/Users/tester"
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["\(home)/Music/Cubase", "/Volumes/Archive"],
            songCount: 6,
            songsWithWarningsCount: 0,
            totalSongWarningCount: 0,
            globalWarnings: [],
            songWarningSummaries: [],
            skippedEntries: []
        )

        XCTAssertEqual(
            diagnostics.displayRootPaths(homeDirectory: home),
            ["~/Music/Cubase", "/Volumes/Archive"]
        )
    }

    func testSummaryLineDescribesCleanScan() {
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["/tmp/fixture"],
            songCount: 6,
            songsWithWarningsCount: 0,
            totalSongWarningCount: 0,
            globalWarnings: [],
            songWarningSummaries: [],
            skippedEntries: []
        )

        XCTAssertEqual(
            diagnostics.summaryLine,
            "Scanned 6 songs · no warnings · nothing skipped at roots"
        )
    }
}
