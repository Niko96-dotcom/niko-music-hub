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
        XCTAssertTrue(text.contains("songs=9"))
        XCTAssertTrue(text.contains("songs_with_warnings=1"))
        XCTAssertTrue(text.contains("skipped_entries=2"))
        XCTAssertTrue(text.contains("summary_line=roots: "))
        XCTAssertTrue(text.contains("CubaseArchive"))
        XCTAssertTrue(
            text.contains(
                "· Scanned 9 songs · 1 song(s) with 1 warning(s) — Broken Folder Example · 2 skipped at roots"
            )
        )
        XCTAssertFalse(text.contains(home))
        XCTAssertTrue(text.contains("~/"))
    }

    func testFormattedTextIncludesScanHealthBadgeForFixtureScan() throws {
        try CubaseFixtures.ensureGenerated()
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [archiveRoot],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: "/Users/test"
        )

        XCTAssertEqual(
            ArchiveDiagnosticsPanelContext.rootHealthBadge(for: diagnostics),
            "1 song warning · 2 skipped at roots"
        )
        XCTAssertTrue(text.contains("root_health_badge=1 song warning · 2 skipped at roots"))
    }

    func testFormattedTextIncludesRootHealthBadgeForInvalidRootScan() {
        let missing = URL(fileURLWithPath: "/tmp/niko-music-hub-missing-root", isDirectory: true)
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: ScanResult(
                songs: [],
                globalWarnings: ["Root is not a directory: \(missing.path)"],
                skippedEntries: [
                    SkippedScanEntry(
                        kind: .invalidRoot,
                        label: missing.path,
                        reason: "Root is not a directory"
                    ),
                ]
            ),
            roots: [missing],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: "/Users/test"
        )

        XCTAssertTrue(text.contains("root_health_badge=1 invalid root · 1 root warning"))
    }

    func testFormattedTextIncludesSummaryLineForSupportPaste() {
        let home = "/Users/tester"
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
            rootPaths: ["\(home)/Music/Cubase"],
            songCount: 3,
            songsWithWarningsCount: 0,
            totalSongWarningCount: 0,
            globalWarnings: [],
            songWarningSummaries: [],
            skippedEntries: []
        )

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: home
        )

        XCTAssertTrue(
            text.contains(
                "summary_line=roots: ~/Music/Cubase · Scanned 3 songs · no warnings · nothing skipped at roots"
            )
        )
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

    func testFormattedTextIncludesPreviewRankingPanelContext() throws {
        try CubaseFixtures.ensureGenerated()
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [archiveRoot],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let lab = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Preview Ranking Lab" })
        let selectedContext = ArchiveDiagnosticsSelectedSongContext.from(song: lab)

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: "/Users/test",
            selectedSongContext: selectedContext
        )

        XCTAssertTrue(text.contains("preview_ranking_tiebreak_legend="))
        XCTAssertTrue(text.contains("CPR version anchor"))
        XCTAssertTrue(text.contains("too_short_non_main="))
        XCTAssertTrue(text.contains("songs_with_too_short="))
        XCTAssertTrue(
            text.contains(
                "too_short_song=Lab Song count=1 clips=Lab Song short clip.wav"
            )
        )
        XCTAssertTrue(text.contains("preview_ranking_scan_callout="))
        XCTAssertTrue(text.contains("too short preview"))
        XCTAssertTrue(text.contains("preview_ranking_selected_header="))
        XCTAssertTrue(text.contains("Main preview:"))
        XCTAssertTrue(text.contains("skipped too short:"))
    }

    func testFormattedTextIncludesEqualScoreVersionTiebreakExport() throws {
        try CubaseFixtures.ensureGenerated()
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let lab = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Equal Score Version Tiebreak" })
        let selectedContext = ArchiveDiagnosticsSelectedSongContext.from(song: lab)

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: ArchiveScanDiagnosticsBuilder.build(
                result: result,
                roots: [archiveRoot],
                scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            homeDirectory: "/Users/test",
            selectedSongContext: selectedContext
        )

        XCTAssertTrue(text.contains("selected_song_title=Tie Song"))
        XCTAssertTrue(text.contains("preview_rank_tiebreak=Equal score — version v3 beat v2"))
        XCTAssertTrue(text.contains("Tie Song v3 mix.wav"))
    }

    func testFormattedTextIncludesEqualScoreExtensionTiebreakExport() throws {
        try CubaseFixtures.ensureGenerated()
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let lab = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Equal Score Extension Tiebreak" })
        let selectedContext = ArchiveDiagnosticsSelectedSongContext.from(song: lab)

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: ArchiveScanDiagnosticsBuilder.build(
                result: result,
                roots: [archiveRoot],
                scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            homeDirectory: "/Users/test",
            selectedSongContext: selectedContext
        )

        XCTAssertTrue(text.contains("selected_song_title=Tie Song"))
        XCTAssertTrue(text.contains("preview_rank_tiebreak=Equal score — preferred flac over mp3"))
        XCTAssertTrue(text.contains("Tie Song mix.flac"))
    }

    func testFormattedTextIncludesEqualScoreTiebreakExportForTiebreakLab() throws {
        try CubaseFixtures.ensureGenerated()
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let lab = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Equal Score Duration Tiebreak" })
        let selectedContext = ArchiveDiagnosticsSelectedSongContext.from(song: lab)

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: ArchiveScanDiagnosticsBuilder.build(
                result: result,
                roots: [archiveRoot],
                scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            homeDirectory: "/Users/test",
            selectedSongContext: selectedContext
        )

        XCTAssertTrue(text.contains("selected_song_title=Tie Song"))
        XCTAssertTrue(text.contains("preview_rank_tiebreak=Equal score — longer preview"))
        XCTAssertTrue(text.contains("Tie Song mix long.wav"))
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
        let lab = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Preview Ranking Lab" })
        let selectedContext = ArchiveDiagnosticsSelectedSongContext.from(song: lab)

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: "/Users/test",
            selectedSongContext: selectedContext
        )

        XCTAssertTrue(text.contains("selected_song_title=Lab Song"))
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

    func testFormattedTextIncludesSummaryLineTruncationMetadataWhenManySongWarnings() {
        let summaries = (1...8).map { index in
            SongWarningSummary(displayTitle: "Song \(index)", warnings: ["warn \(index)"])
        }
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
            rootPaths: ["/tmp/fixture"],
            songCount: 8,
            songsWithWarningsCount: 8,
            totalSongWarningCount: 8,
            globalWarnings: [],
            songWarningSummaries: summaries,
            skippedEntries: []
        )

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: nil
        )

        XCTAssertTrue(text.contains("summary_line_song_warning_titles_truncated=true"))
        XCTAssertTrue(text.contains("summary_line_song_warning_titles_cap=5"))
        XCTAssertTrue(text.contains("summary_line_song_warning_titles_omitted=3"))
        XCTAssertTrue(text.contains("and 3 more"))
    }

    func testFormattedTextOmitsSummaryLineTruncationMetadataWhenUnderCap() {
        let summaries = [
            SongWarningSummary(displayTitle: "Broken Song", warnings: ["missing cpr"]),
        ]
        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
            rootPaths: ["/tmp/fixture"],
            songCount: 1,
            songsWithWarningsCount: 1,
            totalSongWarningCount: 1,
            globalWarnings: [],
            songWarningSummaries: summaries,
            skippedEntries: []
        )

        let text = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: nil
        )

        XCTAssertFalse(text.contains("summary_line_song_warning_titles_truncated="))
        XCTAssertFalse(text.contains("summary_line_song_warning_titles_cap="))
        XCTAssertFalse(text.contains("summary_line_song_warning_titles_omitted="))
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
