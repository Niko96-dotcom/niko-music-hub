import XCTest
@testable import NikoMusicCore

final class ArchiveScanDiagnosticsBuilderTests: XCTestCase {
    func testBuildAggregatesCountsWarningsAndSkipped() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let roots = [CubaseFixtures.archiveRoot]
        let result = try scanner.scan(roots: roots)
        let scannedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: roots,
            scannedAt: scannedAt
        )

        XCTAssertEqual(diagnostics.scannedAt, scannedAt)
        XCTAssertEqual(diagnostics.rootPaths, [CubaseFixtures.archiveRoot.path])
        XCTAssertEqual(diagnostics.songCount, 5)
        XCTAssertEqual(diagnostics.songsWithWarningsCount, 1)
        XCTAssertGreaterThanOrEqual(diagnostics.totalSongWarningCount, 1)
        XCTAssertTrue(diagnostics.globalWarnings.isEmpty)
        XCTAssertTrue(
            diagnostics.songWarningSummaries.contains { $0.displayTitle == "Broken Folder Example" }
        )
        XCTAssertTrue(
            diagnostics.skippedEntries.contains { $0.kind == .nonFolderAtRoot && $0.label == "LOOSE_FILE.txt" }
        )
        XCTAssertGreaterThanOrEqual(diagnostics.previewRankingPanel.tooShortNonMainPreviewCount, 1)
        XCTAssertNotNil(diagnostics.previewRankingPanel.scanHeaderCallout)
    }

    func testBuildIncludesInvalidRootWarning() {
        let missing = URL(fileURLWithPath: "/tmp/niko-music-hub-missing-root", isDirectory: true)
        let result = ScanResult(
            songs: [],
            globalWarnings: ["Root is not a directory: \(missing.path)"],
            skippedEntries: [
                SkippedScanEntry(
                    kind: .invalidRoot,
                    label: missing.path,
                    reason: "Root is not a directory"
                )
            ]
        )
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [missing],
            scannedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(diagnostics.songCount, 0)
        XCTAssertEqual(diagnostics.globalWarnings.count, 1)
        XCTAssertEqual(diagnostics.skippedEntries.count, 1)
        XCTAssertEqual(diagnostics.skippedEntries.first?.kind, .invalidRoot)
    }
}
