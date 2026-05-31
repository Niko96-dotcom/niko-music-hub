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

        XCTAssertNoThrow(try result.validateForE2ESmoke(dryRunOpen: true))

        XCTAssertGreaterThanOrEqual(result.core.songCount, 4)
        XCTAssertGreaterThanOrEqual(result.fixtureDiagnostics.songCount, 4)
        XCTAssertEqual(
            result.fixtureDiagnostics.healthBadge,
            "1 song warning · 2 skipped at roots"
        )
        XCTAssertEqual(result.core.dryRunCPRDisplayPath, Song.displayDryRunPath(result.core.dryRunCPRPath))
        XCTAssertTrue(result.core.dryRunLogLine?.contains("[dry-run] open CPR:") == true)
        if let dryRunLogLine = result.core.dryRunLogLine {
            XCTAssertEqual(
                result.core.dryRunLogDisplayLine,
                DiagnosticsPathRedactor.redactPathsInText(dryRunLogLine)
            )
        }
        XCTAssertEqual(
            ArchiveDiagnosticsPanelAccessibility.rootHealthBadge,
            "archive_diagnostics_root_health_badge"
        )
    }
}
