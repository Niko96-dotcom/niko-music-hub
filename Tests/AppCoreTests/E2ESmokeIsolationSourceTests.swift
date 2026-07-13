import XCTest

/// Guards the e2e smoke's isolation from the user's real Application Support data.
///
/// Every app launch in `script/e2e_user_smoke.sh` must set NIKO_MUSIC_HUB_SETTINGS_SUITE,
/// which routes settings and Application Support (archive-index.sqlite, output-inbox.json)
/// into "Niko Music Hub/Isolated/<suite>/". Overriding $HOME does NOT isolate anything —
/// FileManager.urls(for: .applicationSupportDirectory) ignores the environment variable —
/// and a suite-less smoke run overwrites the user's real archive cache with fixture data
/// (observed 2026-07-12).
final class E2ESmokeIsolationSourceTests: XCTestCase {
    func testArchiveSmokeRunsInIsolatedSettingsSuite() throws {
        let script = try smokeScriptSource()
        XCTAssertTrue(
            script.contains(#"export NIKO_MUSIC_HUB_SETTINGS_SUITE="$ARCHIVE_SUITE""#),
            "The archive smoke launch must export NIKO_MUSIC_HUB_SETTINGS_SUITE so the app-under-smoke cannot touch the real archive cache"
        )
        XCTAssertFalse(
            script.contains("export HOME="),
            "Overriding $HOME does not isolate Application Support — use NIKO_MUSIC_HUB_SETTINGS_SUITE instead"
        )
    }

    func testSmokeCleansUpIsolatedSuites() throws {
        let script = try smokeScriptSource()
        XCTAssertTrue(
            script.contains(#"rm -rf "$ISOLATED_ROOT/$ARCHIVE_SUITE" "$ISOLATED_ROOT/$UI_SUITE""#),
            "Smoke runs must remove their Isolated/<suite> directories so they do not accumulate"
        )
    }

    func testEveryBuildAndRunLaunchCarriesTheIsolatedSuite() throws {
        let script = try smokeScriptSource()
        let launchLines = script.split(separator: "\n").filter { $0.contains("./script/build_and_run.sh") }
        XCTAssertFalse(launchLines.isEmpty)
        XCTAssertTrue(
            launchLines.allSatisfy { $0.contains(#"NIKO_MUSIC_HUB_SETTINGS_SUITE="$UI_SUITE""#) },
            "A suite-less build_and_run launch can reuse the real app process and expose the user's archive"
        )
    }

    func testSmokeForceStopsAppsBeforeAndAfterLaunches() throws {
        let script = try smokeScriptSource()
        XCTAssertGreaterThanOrEqual(
            script.components(separatedBy: "nmh_stop_app true").count - 1,
            2,
            "Smoke must force-stop any old app before the isolated launch and stop the isolated app during cleanup"
        )
    }

    func testAXDumpIsWindowOnlyAndCannotCollectSystemRecentItems() throws {
        let probe = try SourceTestSupport.read("script/ui_probe.swift")
        XCTAssertTrue(probe.contains("Window-only output avoids collecting unrelated system menu/recent-item data"))
        XCTAssertFalse(probe.contains("dumpAX(app, depth:"))
    }

    private func smokeScriptSource() throws -> String {
        try SourceTestSupport.read("script/e2e_user_smoke.sh")
    }
}
