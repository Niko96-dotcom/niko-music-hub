import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsSkippedEntriesPanelContextTests: XCTestCase {
    func testPanelLineFormatsLabelAndReason() {
        let line = ArchiveDiagnosticsSkippedEntriesPanelContext.panelLine(
            label: "LOOSE_FILE.txt",
            reason: SkippedScanEntry.standardNonFolderAtRootReason
        )
        XCTAssertTrue(line.contains("LOOSE_FILE.txt"))
        XCTAssertTrue(line.contains("Not a folder"))
    }

    func testFixtureScanSkippedEntriesPanelMatchesExporter() throws {
        try CubaseFixtures.ensureGenerated()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let archiveRoot = CubaseFixtures.archiveRoot
        let result = try CubaseArchiveScanner().scan(roots: [archiveRoot])
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: [archiveRoot],
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let exportText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: home
        )
        let displaySkipped = diagnostics.displaySkippedEntries(homeDirectory: home)
        XCTAssertEqual(displaySkipped.count, 2)
        XCTAssertTrue(
            ArchiveDiagnosticsSkippedEntriesPanelContext.linesMatchExport(
                in: exportText,
                entries: displaySkipped,
                homeDirectory: home
            )
        )
        XCTAssertTrue(displaySkipped.contains { $0.label == "LOOSE_FILE.txt" })
        XCTAssertTrue(displaySkipped.contains { $0.label == "README.md" })
    }
}
