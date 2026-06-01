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

    func testDisplayGlobalWarningsRedactsEmbeddedHomePaths() {
        let home = "/Users/tester"
        let embedded = "\(home)/Music/Cubase/Neon Hook/Neon Hook.cpr"
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: [],
            songCount: 1,
            songsWithWarningsCount: 0,
            totalSongWarningCount: 0,
            globalWarnings: ["Root is not a directory: \(embedded)"],
            songWarningSummaries: [],
            skippedEntries: []
        )

        XCTAssertEqual(
            diagnostics.displayGlobalWarnings(homeDirectory: home),
            ["Root is not a directory: ~/Music/Cubase/Neon Hook/Neon Hook.cpr"]
        )
    }

    func testDisplaySkippedEntriesRedactsLabelAndReason() {
        let home = "/Users/tester"
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: [],
            songCount: 0,
            songsWithWarningsCount: 0,
            totalSongWarningCount: 0,
            globalWarnings: [],
            songWarningSummaries: [],
            skippedEntries: [
                SkippedScanEntry(
                    kind: .invalidRoot,
                    label: "\(home)/Music/LOOSE.cpr",
                    reason: "Skipped invalid root at \(home)/Music/LOOSE.cpr"
                ),
            ]
        )

        let display = diagnostics.displaySkippedEntries(homeDirectory: home)
        XCTAssertEqual(display.count, 1)
        XCTAssertEqual(display[0].label, "~/Music/LOOSE.cpr")
        XCTAssertEqual(display[0].reason, "Skipped invalid root at ~/Music/LOOSE.cpr")
    }

    func testDisplaySongWarningSummariesRedactsEmbeddedPaths() {
        let home = "/Users/tester"
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: [],
            songCount: 1,
            songsWithWarningsCount: 1,
            totalSongWarningCount: 1,
            globalWarnings: [],
            songWarningSummaries: [
                SongWarningSummary(
                    displayTitle: "Broken Folder",
                    warnings: ["Missing mixdown under \(home)/Music/Broken"]
                ),
            ],
            skippedEntries: []
        )

        let display = diagnostics.displaySongWarningSummaries(homeDirectory: home)
        XCTAssertEqual(display.count, 1)
        XCTAssertEqual(display[0].warnings, ["Missing mixdown under ~/Music/Broken"])
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

    func testSummaryLineIncludesSongWarningTitlesWhenPresent() {
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["/tmp/fixture"],
            songCount: 3,
            songsWithWarningsCount: 2,
            totalSongWarningCount: 3,
            globalWarnings: [],
            songWarningSummaries: [
                SongWarningSummary(displayTitle: "Zebra Song", warnings: ["warn z"]),
                SongWarningSummary(displayTitle: "Alpha Song", warnings: ["warn a", "warn a2"]),
            ],
            skippedEntries: []
        )

        XCTAssertEqual(
            diagnostics.summaryLine,
            "Scanned 3 songs · 2 song(s) with 3 warning(s) — Alpha Song, Zebra Song · nothing skipped at roots"
        )
    }

    func testSummaryLineSongWarningTitlesTruncationFootnoteWhenTruncated() {
        let summaries = (1...8).map { index in
            SongWarningSummary(displayTitle: "Song \(index)", warnings: ["warn \(index)"])
        }
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["/tmp/fixture"],
            songCount: 8,
            songsWithWarningsCount: 8,
            totalSongWarningCount: 8,
            globalWarnings: [],
            songWarningSummaries: summaries,
            skippedEntries: []
        )

        XCTAssertEqual(
            diagnostics.summaryLineSongWarningTitlesTruncationFootnote,
            "Support summary shows 5 warning song titles; 3 more listed below."
        )
    }

    func testSummaryLineSongWarningTitlesTruncationFootnoteNilWhenNotTruncated() {
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["/tmp/fixture"],
            songCount: 3,
            songsWithWarningsCount: 1,
            totalSongWarningCount: 1,
            globalWarnings: [],
            songWarningSummaries: [
                SongWarningSummary(displayTitle: "Alpha Song", warnings: ["warn"]),
            ],
            skippedEntries: []
        )

        XCTAssertNil(diagnostics.summaryLineSongWarningTitlesTruncationFootnote)
    }

    func testSummaryLineSongWarningTitlesTruncatedWhenOverCap() {
        let summaries = (1...8).map { index in
            SongWarningSummary(displayTitle: "Song \(index)", warnings: ["warn \(index)"])
        }
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["/tmp/fixture"],
            songCount: 8,
            songsWithWarningsCount: 8,
            totalSongWarningCount: 8,
            globalWarnings: [],
            songWarningSummaries: summaries,
            skippedEntries: []
        )

        XCTAssertTrue(diagnostics.summaryLineSongWarningTitlesTruncated)
        XCTAssertEqual(diagnostics.summaryLineSongWarningTitlesOmittedCount, 3)
    }

    func testSummaryLineSongWarningTitlesNotTruncatedAtCap() {
        let summaries = (1...5).map { index in
            SongWarningSummary(displayTitle: "Song \(index)", warnings: ["warn \(index)"])
        }
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["/tmp/fixture"],
            songCount: 5,
            songsWithWarningsCount: 5,
            totalSongWarningCount: 5,
            globalWarnings: [],
            songWarningSummaries: summaries,
            skippedEntries: []
        )

        XCTAssertFalse(diagnostics.summaryLineSongWarningTitlesTruncated)
        XCTAssertEqual(diagnostics.summaryLineSongWarningTitlesOmittedCount, 0)
    }

    func testSummaryLineTruncatesManySongWarningTitles() {
        let summaries = (1...8).map { index in
            SongWarningSummary(displayTitle: "Song \(index)", warnings: ["warn \(index)"])
        }
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["/tmp/fixture"],
            songCount: 8,
            songsWithWarningsCount: 8,
            totalSongWarningCount: 8,
            globalWarnings: [],
            songWarningSummaries: summaries,
            skippedEntries: []
        )

        XCTAssertEqual(
            diagnostics.summaryLine,
            "Scanned 8 songs · 8 song(s) with 8 warning(s) — Song 1, Song 2, Song 3, Song 4, Song 5 and 3 more · nothing skipped at roots"
        )
    }

    func testExportSummaryLineIncludesRedactedRootsAndScanCounts() {
        let home = "/Users/tester"
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["\(home)/Music/Cubase", "/Volumes/Archive"],
            songCount: 5,
            songsWithWarningsCount: 1,
            totalSongWarningCount: 2,
            globalWarnings: [],
            songWarningSummaries: [
                SongWarningSummary(displayTitle: "Broken Song", warnings: ["missing cpr", "no mixdown"]),
            ],
            skippedEntries: [
                SkippedScanEntry(kind: .nonFolderAtRoot, label: "LOOSE.txt", reason: "Not a song folder")
            ]
        )

        XCTAssertEqual(
            diagnostics.exportSummaryLine(homeDirectory: home),
            "roots: ~/Music/Cubase, /Volumes/Archive · Scanned 5 songs · 1 song(s) with 2 warning(s) — Broken Song · 1 skipped at roots"
        )
    }
}
