import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsGlobalWarningsPanelContextTests: XCTestCase {
    func testPanelLineUsesWarningTextOnly() {
        let line = ArchiveDiagnosticsGlobalWarningsPanelContext.panelLine(
            warning: "Root is not a directory: ~/Music/missing"
        )
        XCTAssertEqual(line, "Root is not a directory: ~/Music/missing")
    }

    func testLineMatchesExportForGlobalWarning() {
        let export = """
        global_warning=Root is not a directory: ~/Music/missing
        """
        XCTAssertTrue(
            ArchiveDiagnosticsGlobalWarningsPanelContext.lineMatchesExport(
                in: export,
                warning: "Root is not a directory: ~/Music/missing"
            )
        )
    }

    func testInvalidRootScanGlobalWarningsPanelMatchesExporter() {
        let missing = URL(fileURLWithPath: "/tmp/niko-music-hub-missing-root", isDirectory: true)
        let home = "/Users/test"
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
        let exportText = ArchiveDiagnosticsExporter.formattedText(
            diagnostics: diagnostics,
            homeDirectory: home
        )
        let displayWarnings = diagnostics.displayGlobalWarnings(homeDirectory: home)
        XCTAssertEqual(displayWarnings.count, 1)
        XCTAssertTrue(
            ArchiveDiagnosticsGlobalWarningsPanelContext.linesMatchExport(
                in: exportText,
                warnings: displayWarnings,
                homeDirectory: home
            )
        )
    }
}
