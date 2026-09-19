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

    func testPublicUILaunchUsesExactBinaryPIDAndIsolatedSuite() throws {
        let script = try smokeScriptSource()
        XCTAssertTrue(script.contains(#"NIKO_MUSIC_HUB_SETTINGS_SUITE="$UI_SUITE" \"#))
        XCTAssertTrue(script.contains(#""$APP_BINARY" >"$PUBLIC_UI_LOG" 2>&1 &"#))
        XCTAssertTrue(script.contains("PUBLIC_UI_PID=$!"))
        XCTAssertTrue(script.contains(#"--pid "$PUBLIC_UI_PID""#))
        XCTAssertTrue(script.contains(#"--binary-path "$APP_BINARY""#))
        XCTAssertFalse(
            script.contains("pgrep -x NikoMusicHub"),
            "Selecting the newest process can attach to a normally configured app and expose the user's archive"
        )
        XCTAssertFalse(
            script.contains("./script/build_and_run.sh"),
            "The public UI smoke must launch the already-built exact binary, not ask LaunchServices to find or reuse an app"
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

        let script = try smokeScriptSource()
        XCTAssertFalse(
            script.contains("screencapture -x"),
            "Smoke screenshots must target the isolated app window instead of capturing the user's full desktop"
        )
        XCTAssertTrue(script.contains(#"--capture "$PUBLIC_UI_SCREENSHOT""#))
    }

    func testPublicUIAccessibilityReadinessIsBoundedAndFailClosed() throws {
        let script = try smokeScriptSource()
        XCTAssertTrue(script.contains("PUBLIC_UI_DEADLINE=$((SECONDS + 20))"))
        // The readiness marker must be copy the first-run view really renders: the
        // 1.6.0 rewording turned the strict release gate red for a stale string.
        let readinessMarker = "Choose the folder that holds your song projects"
        XCTAssertTrue(script.contains("grep -Fq \"\(readinessMarker)\""))
        let firstRunView = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/ArchiveFirstRunView.swift")
        XCTAssertTrue(
            firstRunView.contains(readinessMarker),
            "e2e_user_smoke.sh waits for first-run copy that ArchiveFirstRunView no longer renders"
        )
        XCTAssertTrue(script.contains("strict UI mode requires AX-visible first-run content"))
    }

    func testFullDeveloperCheckRequiresAccessibilityVisibleUI() throws {
        let devScript = try SourceTestSupport.read("script/dev.sh")
        XCTAssertTrue(
            devScript.contains("env NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh"),
            "A green ./script/dev.sh check must not silently downgrade an inaccessible UI smoke to a visible-window-only result"
        )
    }

    private func smokeScriptSource() throws -> String {
        try SourceTestSupport.read("script/e2e_user_smoke.sh")
    }
}
