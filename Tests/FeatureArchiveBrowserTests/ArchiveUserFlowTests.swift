import AppCore
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

@MainActor
final class ArchiveUserFlowTests: XCTestCase {
    func testFixtureUserFlowScanSearchOpenDryRunLeavesArchiveUnchanged() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        setenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN", "1", 1)
        defer {
            unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
            unsetenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN")
        }

        let result = try ArchiveUserFlowSmoke.run(
            fixtureRoot: CubaseFixtures.archiveRoot,
            context: TestToolContext.make()
        )

        XCTAssertEqual(result.userFlow, "scan_search_open")
        XCTAssertGreaterThanOrEqual(result.songCount, 4)
        XCTAssertEqual(result.searchQuery, "neon hk")
        XCTAssertEqual(result.searchMatchCount, 1)
        XCTAssertEqual(result.selectedTitle, "Neon Hook")
        XCTAssertGreaterThanOrEqual(result.diagnosticsSongCount, 4)
        XCTAssertGreaterThanOrEqual(result.diagnosticsSkippedCount, 1)
        XCTAssertTrue(result.writeProbeDenied)
        XCTAssertTrue(result.archiveTreeUnchanged)
        XCTAssertTrue(result.dryRunCPRPath.contains("Neon Hook"))
        XCTAssertTrue(result.dryRunCPRPath.hasSuffix("Neon Hook.cpr"))
        XCTAssertEqual(result.dryRunCPRDisplayPath, Song.displayDryRunPath(result.dryRunCPRPath))
        XCTAssertTrue(result.dryRunLogLine?.contains("[dry-run] open CPR:") == true)
        if let dryRunLogLine = result.dryRunLogLine {
            XCTAssertEqual(
                result.dryRunLogDisplayLine,
                DiagnosticsPathRedactor.redactPathsInText(dryRunLogLine)
            )
        }
        XCTAssertTrue(result.searchMatchSummary.contains("neon"))
        XCTAssertTrue(result.searchMatchSummary.contains("hk"))
        XCTAssertFalse(result.searchDiagnosticsExportPath.isEmpty)
        XCTAssertTrue(result.searchDiagnosticsExportContainsMatch)
        XCTAssertTrue(result.rankingLabMainPreviewSummary.contains("Lab Song v3 mix.wav"))
        XCTAssertTrue(result.rankingLabMainPreviewSummary.contains("v3"))
        XCTAssertTrue(result.rankingLabMainPreviewSummary.contains("wav"))
        XCTAssertFalse(result.rankingLabDiagnosticsExportPath.isEmpty)
        XCTAssertTrue(result.rankingLabDiagnosticsExportContainsMatch)
        XCTAssertFalse(result.tiebreakLabDiagnosticsExportPath.isEmpty)
        XCTAssertTrue(result.tiebreakLabDiagnosticsExportContainsTiebreak)
        XCTAssertTrue(
            result.brokenFolderDisplayWarnings.contains(where: { $0.localizedCaseInsensitiveContains("CPR") })
        )
        XCTAssertEqual(result.brokenFolderSidecarNotes, "notes only")
        XCTAssertEqual(result.warningSearchQuery, "project")
        XCTAssertEqual(result.warningSearchMatchCount, 1)
        XCTAssertEqual(result.warningSearchMatchTitle, "Broken Folder Example")
        XCTAssertTrue(result.warningSearchMatchSummary.contains("scan warning"))
        XCTAssertTrue(result.warningSearchMatchSummary.contains("project"))
        XCTAssertFalse(result.warningSearchDiagnosticsExportPath.isEmpty)
        XCTAssertTrue(result.warningSearchDiagnosticsExportContainsMatch)
        XCTAssertEqual(result.skippedSearchQuery, "LOOSE_FILE.txt")
        XCTAssertGreaterThanOrEqual(result.skippedSearchMatchCount, 1)
        XCTAssertEqual(result.skippedSearchMatchLabel, "LOOSE_FILE.txt")
        XCTAssertTrue(result.skippedSearchMatchSummary.contains("skipped label"))
        XCTAssertFalse(result.skippedSearchDiagnosticsExportPath.isEmpty)
        XCTAssertTrue(result.skippedSearchDiagnosticsExportContainsMatch)
    }
}
