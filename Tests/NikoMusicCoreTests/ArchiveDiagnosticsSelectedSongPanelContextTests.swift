import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsSelectedSongPanelContextTests: XCTestCase {
    func testPanelTitleLineIncludesDisplayTitle() {
        let line = ArchiveDiagnosticsSelectedSongPanelContext.panelTitleLine(
            displayTitle: "Broken Folder Example"
        )
        XCTAssertEqual(line, "Broken Folder Example")
    }

    func testPanelCprLineIncludesSummary() {
        let line = ArchiveDiagnosticsSelectedSongPanelContext.panelCprLine(
            cprSummary: "no CPR versions"
        )
        XCTAssertTrue(line.contains("no CPR versions"))
    }

    func testPanelWarningLineIncludesWarning() {
        let line = ArchiveDiagnosticsSelectedSongPanelContext.panelWarningLine(
            warning: "No CPR project files found"
        )
        XCTAssertTrue(line.contains("No CPR project files found"))
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
        let export = "selected_song_cpr=no CPR versions"
        XCTAssertTrue(
            ArchiveDiagnosticsSelectedSongPanelContext.cprLineMatchesExport(
                in: export,
                cprSummary: "no CPR versions"
            )
        )
    }

    func testWarningLinesMatchExport() {
        let export = "selected_song_warning=No CPR project files found"
        XCTAssertTrue(
            ArchiveDiagnosticsSelectedSongPanelContext.warningLinesMatchExport(
                in: export,
                warningLines: ["No CPR project files found"]
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
