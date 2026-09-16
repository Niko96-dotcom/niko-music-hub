import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsSelectedSongPanelContextTests: XCTestCase {
    func testPanelCprLineIncludesSummary() {
        let line = ArchiveDiagnosticsSelectedSongPanelContext.panelCprLine(
            cprSummary: "no project versions"
        )
        XCTAssertTrue(line.contains("no project versions"))
    }

    func testPanelNotesLineIncludesNotes() {
        let line = ArchiveDiagnosticsSelectedSongPanelContext.panelNotesLine(notes: "notes only")
        XCTAssertTrue(line.contains("notes only"))
    }

    /// NMH-092: diagnostics notes use the plain "Companion notes" label, not jargon.
    func testPanelNotesLineUsesCompanionNotesLabel() {
        let line = ArchiveDiagnosticsSelectedSongPanelContext.panelNotesLine(notes: "notes only")
        XCTAssertTrue(line.hasPrefix("Companion notes · "))
        XCTAssertTrue(line.contains("notes only"))
        XCTAssertFalse(line.contains("Sidecar"))
    }

    /// NMH-092: diagnostics panel uses the plain short-preview heading.
    func testDiagnosticsPanelUsesPlainShortPreviewHeading() throws {
        let panel = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveDiagnosticsPanelView.swift",
            encoding: .utf8
        )
        XCTAssertTrue(panel.contains("Short preview files (not the main mix)"))
        XCTAssertFalse(panel.contains("Too short previews (not main)"))
    }

    /// NMH-092: detail header uses the plain "Companion notes" label.
    func testDetailHeaderUsesCompanionNotes() throws {
        let detail = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/SongDetailView.swift",
            encoding: .utf8
        )
        XCTAssertTrue(detail.contains("HubSectionHeader(\"Companion notes\")"))
        XCTAssertFalse(detail.contains("Sidecar notes"))
    }

    /// NMH-092: expanded diagnostics live in a 360 pt sheet, not a 140 pt inline box.
    func testDiagnosticsExpandsInSheetInsteadOfCrampedInline() throws {
        let more = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveSidebarMorePanel.swift",
            encoding: .utf8
        )
        XCTAssertTrue(more.contains("Show Diagnostics"))
        XCTAssertTrue(more.contains("minHeight: 360"))
        XCTAssertTrue(more.contains("minWidth: 420"))
        XCTAssertTrue(more.contains(".keyboardShortcut(.cancelAction)"))
        XCTAssertFalse(more.contains("maxHeight: 140"))
    }

    func testTitleLineMatchesExport() {
        let export = """
        selected_song
        selected_song_title=Broken Folder Example
        """
        XCTAssertTrue(
            ArchiveDiagnosticsSelectedSongPanelContext.titleLineMatchesExport(
                in: export,
                displayTitle: "Broken Folder Example"
            )
        )
    }

    func testCprLineMatchesExport() {
        let export = "selected_song_cpr=no project versions"
        XCTAssertTrue(
            ArchiveDiagnosticsSelectedSongPanelContext.cprLineMatchesExport(
                in: export,
                cprSummary: "no project versions"
            )
        )
    }

    func testWarningLinesMatchExport() {
        let export = "selected_song_warning=No project files (.cpr or .als) found"
        XCTAssertTrue(
            ArchiveDiagnosticsSelectedSongPanelContext.warningLinesMatchExport(
                in: export,
                warningLines: ["No project files (.cpr or .als) found"]
            )
        )
    }

    func testNotesLineMatchesExport() {
        let export = "selected_song_notes=notes only"
        XCTAssertTrue(
            ArchiveDiagnosticsSelectedSongPanelContext.notesLineMatchesExport(
                in: export,
                notes: "notes only"
            )
        )
    }

    func testFixtureBrokenFolderPanelMatchesExporter() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let broken = try XCTUnwrap(result.songs.first { $0.displayTitle == "Broken Folder Example" })
        let context = ArchiveDiagnosticsSelectedSongContext.from(song: broken)
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [CubaseFixtures.archiveRoot]
        )
        let exportText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: nil,
            selectedSongContext: context
        )

        XCTAssertTrue(
            ArchiveDiagnosticsSelectedSongPanelContext.titleLineMatchesExport(
                in: exportText,
                displayTitle: context.displayTitle
            )
        )
        XCTAssertTrue(
            ArchiveDiagnosticsSelectedSongPanelContext.cprLineMatchesExport(
                in: exportText,
                cprSummary: context.cprSummary
            )
        )
        XCTAssertTrue(
            ArchiveDiagnosticsSelectedSongPanelContext.warningLinesMatchExport(
                in: exportText,
                warningLines: context.warningLines
            )
        )
        XCTAssertTrue(
            ArchiveDiagnosticsSelectedSongPanelContext.notesLineMatchesExport(
                in: exportText,
                notes: context.sidecarNotesLine ?? ""
            )
        )
    }
}
