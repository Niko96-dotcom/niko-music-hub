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
