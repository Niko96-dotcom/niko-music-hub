import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsExporterTests: XCTestCase {
    func testExportWritesRedactedTextOutsideArchiveRoots() throws {
        try CubaseFixtures.ensureGenerated()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [archiveRoot],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertTrue(diagnostics.rootPaths.first?.hasPrefix(home) == true)

        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("niko-diagnostics-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDir) }

        let destination = exportDir.appendingPathComponent("scan-diagnostics.txt")
        try ArchiveDiagnosticsExporter.exportText(
            diagnostics: diagnostics,
            to: destination,
            archiveRoots: [archiveRoot],
            homeDirectory: home
        )

        let text = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(text.contains("songs=4"))
        XCTAssertTrue(text.contains("songs_with_warnings=1"))
        XCTAssertFalse(text.contains(home))
        XCTAssertTrue(text.contains("~/"))
    }

    func testFormattedTextIncludesActiveSearchContext() throws {
        try CubaseFixtures.ensureGenerated()
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [archiveRoot],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let searchContext = ArchiveDiagnosticsSearchContext(
            query: "neon hk",
            matches: [
                ArchiveDiagnosticsSearchMatch(
                    displayTitle: "Neon Hook",
                    summary: "neon → title; hk → fuzzy title"
                ),
            ]
        )

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: "/Users/test",
            searchContext: searchContext
        )

        XCTAssertTrue(text.contains("search_query=neon hk"))
        XCTAssertTrue(text.contains("search_matches=1"))
        XCTAssertTrue(text.contains("search_match title=Neon Hook"))
        XCTAssertTrue(text.contains("summary=neon → title; hk → fuzzy title"))
    }

    func testFormattedTextIncludesSelectedSongPreviewRanking() throws {
        try CubaseFixtures.ensureGenerated()
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [archiveRoot],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let lab = try XCTUnwrap(result.songs.first { $0.displayTitle == "Preview Ranking Lab" })
        let mainSummary = try XCTUnwrap(PreviewRankingExplainability.mainPreviewSummary(for: lab))
        let selectedContext = ArchiveDiagnosticsSelectedSongContext(
            displayTitle: lab.displayTitle,
            mainPreviewSummary: mainSummary,
            rankedPreviewLines: PreviewRankingExplainability.rankedPreviewLines(for: lab)
        )

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: "/Users/test",
            selectedSongContext: selectedContext
        )

        XCTAssertTrue(text.contains("selected_song_title=Preview Ranking Lab"))
        XCTAssertTrue(text.contains("main_preview_summary="))
        XCTAssertTrue(text.contains("v3"))
        XCTAssertTrue(text.contains("preview_rank_line="))
    }

    func testExportRejectsDestinationInsideArchiveRoot() throws {
        try CubaseFixtures.ensureGenerated()
        let archiveRoot = CubaseFixtures.archiveRoot
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: ScanResult(),
            roots: [archiveRoot]
        )
        let destination = archiveRoot.appendingPathComponent("scan-diagnostics.txt")

        XCTAssertThrowsError(
            try ArchiveDiagnosticsExporter.exportText(
                diagnostics: diagnostics,
                to: destination,
                archiveRoots: [archiveRoot]
            )
        ) { error in
            XCTAssertEqual(error as? ArchiveDiagnosticsExportError, .destinationInsideArchiveRoot)
        }
    }
}
