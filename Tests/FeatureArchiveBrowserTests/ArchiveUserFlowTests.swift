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
        XCTAssertGreaterThanOrEqual(result.songCount, 3)
        XCTAssertEqual(result.searchQuery, "neon hk")
        XCTAssertEqual(result.searchMatchCount, 1)
        XCTAssertEqual(result.selectedTitle, "Neon Hook")
        XCTAssertGreaterThanOrEqual(result.diagnosticsSongCount, 3)
        XCTAssertGreaterThanOrEqual(result.diagnosticsSkippedCount, 1)
        XCTAssertTrue(result.writeProbeDenied)
        XCTAssertTrue(result.archiveTreeUnchanged)
        XCTAssertTrue(result.dryRunCPRPath.contains("Neon Hook"))
        XCTAssertTrue(result.dryRunCPRPath.hasSuffix("Neon Hook.cpr"))
        XCTAssertTrue(result.dryRunLogLine?.contains("[dry-run] open CPR:") == true)
        XCTAssertTrue(result.searchMatchSummary.contains("neon"))
        XCTAssertTrue(result.searchMatchSummary.contains("hk"))
        XCTAssertTrue(result.rankingLabMainPreviewSummary.contains("Lab Song v3 mix.wav"))
        XCTAssertTrue(result.rankingLabMainPreviewSummary.contains("v3"))
        XCTAssertTrue(result.rankingLabMainPreviewSummary.contains("wav"))
        XCTAssertTrue(
            result.brokenFolderDisplayWarnings.contains(where: { $0.localizedCaseInsensitiveContains("CPR") })
        )
    }
}
