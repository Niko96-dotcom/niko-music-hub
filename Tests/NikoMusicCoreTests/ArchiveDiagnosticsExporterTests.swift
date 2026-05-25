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
        let selectedContext = ArchiveDiagnosticsSelectedSongContext.from(song: lab)

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: "/Users/test",
            selectedSongContext: selectedContext
        )

        XCTAssertTrue(text.contains("selected_song_title=Preview Ranking Lab"))
        XCTAssertTrue(text.contains("main_preview_summary="))
        XCTAssertTrue(text.contains("v3"))
        XCTAssertTrue(text.contains("preview_rank_line="))
        XCTAssertTrue(text.contains("selected_song_cpr=1 version"))
        XCTAssertTrue(text.contains("Preview Ranking Lab.cpr"))
    }

    func testFormattedTextIncludesSelectedSongCPRAndWarnings() throws {
        try CubaseFixtures.ensureGenerated()
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [archiveRoot],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })
        let neonContext = ArchiveDiagnosticsSelectedSongContext.from(song: neon)
        let neonText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: "/Users/test",
            selectedSongContext: neonContext
        )
        XCTAssertTrue(neonText.contains("selected_song_cpr=2 versions"))
        XCTAssertTrue(neonText.contains("latest Neon Hook.cpr"))
        XCTAssertFalse(neonText.contains("selected_song_warning="))

        let broken = try XCTUnwrap(result.songs.first { $0.displayTitle == "Broken Folder Example" })
        let brokenContext = ArchiveDiagnosticsSelectedSongContext.from(song: broken)
        let brokenText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: "/Users/test",
            selectedSongContext: brokenContext
        )
        XCTAssertTrue(brokenText.contains("selected_song_cpr=no CPR versions"))
        XCTAssertTrue(brokenText.contains("selected_song_warning=No CPR project files found"))
        XCTAssertTrue(brokenText.contains("selected_song_notes=notes only"))
        XCTAssertFalse(neonText.contains("selected_song_notes="))
    }

    func testFormattedTextRedactsPathsEmbeddedInWarnings() {
        let home = "/Users/tester"
        let fullPath = "\(home)/Music/Cubase/Neon Hook/Neon Hook.cpr"
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
            rootPaths: [home + "/Music/Cubase"],
            songCount: 1,
            songsWithWarningsCount: 1,
            totalSongWarningCount: 1,
            globalWarnings: ["Root is not a directory: \(fullPath)"],
            songWarningSummaries: [
                SongWarningSummary(
                    displayTitle: "Neon Hook",
                    warnings: ["Latest CPR unreadable: \(fullPath)"]
                ),
            ],
            skippedEntries: []
        )
        let selectedContext = ArchiveDiagnosticsSelectedSongContext(
            displayTitle: "Neon Hook",
            mainPreviewSummary: nil,
            rankedPreviewLines: [],
            cprSummary: "1 version · latest Neon Hook.cpr",
            warningLines: ["Duplicate CPR path: \(fullPath)"]
        )

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: home,
            selectedSongContext: selectedContext
        )

        XCTAssertFalse(text.contains(home))
        XCTAssertTrue(text.contains("~/Music/Cubase/Neon Hook/Neon Hook.cpr"))
        XCTAssertTrue(text.contains("global_warning=Root is not a directory: ~/Music/Cubase/Neon Hook/Neon Hook.cpr"))
        XCTAssertTrue(text.contains("  warning=Latest CPR unreadable: ~/Music/Cubase/Neon Hook/Neon Hook.cpr"))
        XCTAssertTrue(text.contains("selected_song_warning=Duplicate CPR path: ~/Music/Cubase/Neon Hook/Neon Hook.cpr"))
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
