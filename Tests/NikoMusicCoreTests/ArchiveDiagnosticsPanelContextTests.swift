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
        XCTAssertTrue(panel.supportSummaryLine.contains("Scanned 7 songs"))
        XCTAssertTrue(panel.supportSummaryLine.contains("1 song(s) with"))
        XCTAssertTrue(panel.supportSummaryLine.contains("2 skipped at roots"))
    }

    func testRootHealthBadgeShowsSongWarningsAndSkippedOnFixtureScan() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let roots = [CubaseFixtures.archiveRoot]
        let result = try scanner.scan(roots: roots)
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: roots,
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(
            ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics),
            "1 song warning · 2 skipped at roots"
        )
    }

    func testRootHealthBadgeNilWhenScanFullyHealthy() {
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["/tmp/fixture"],
            songCount: 3,
            songsWithWarningsCount: 0,
            totalSongWarningCount: 0,
            globalWarnings: [],
            songWarningSummaries: [],
            skippedEntries: []
        )

        XCTAssertNil(ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics))
    }

    func testRootHealthBadgeShowsInvalidRootCount() {
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["/tmp/missing"],
            songCount: 0,
            songsWithWarningsCount: 0,
            totalSongWarningCount: 0,
            globalWarnings: ["Root is not a directory: /tmp/missing"],
            songWarningSummaries: [],
            skippedEntries: [
                SkippedScanEntry(kind: .invalidRoot, label: "/tmp/missing", reason: "Root is not a directory"),
            ]
        )

        XCTAssertEqual(
            ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics),
            "1 invalid root · 1 root warning"
        )
    }

    func testRootHealthBadgePluralizesMultipleIssues() {
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: [],
            songCount: 0,
            songsWithWarningsCount: 0,
            totalSongWarningCount: 0,
            globalWarnings: [
                "Root is not a directory: /tmp/a",
                "Root is not a directory: /tmp/b",
            ],
            songWarningSummaries: [],
            skippedEntries: [
                SkippedScanEntry(kind: .invalidRoot, label: "/tmp/a", reason: "Root is not a directory"),
                SkippedScanEntry(kind: .invalidRoot, label: "/tmp/b", reason: "Root is not a directory"),
            ]
        )

        XCTAssertEqual(
            ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics),
            "2 invalid roots · 2 root warnings"
        )
    }

    func testRootHealthBadgeShowsGlobalWarningsWithoutInvalidRoots() {
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["/tmp/fixture"],
            songCount: 1,
            songsWithWarningsCount: 0,
            totalSongWarningCount: 0,
            globalWarnings: ["Permission denied reading archive"],
            songWarningSummaries: [],
            skippedEntries: []
        )

        XCTAssertEqual(
            ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics),
            "1 root warning"
        )
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
