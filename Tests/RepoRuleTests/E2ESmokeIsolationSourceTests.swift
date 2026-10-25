import XCTest

/// Guards the E2E smoke's isolation from the person's real Application Support data.
///
/// Every app launch in `script/e2e_user_smoke.sh` must set NIKO_MUSIC_HUB_SETTINGS_SUITE, which routes
/// settings and Application Support (archive-index.sqlite, output-inbox.json) into
/// "Niko Music Hub/Isolated/<suite>/". Overriding $HOME does NOT isolate anything —
/// FileManager.urls(for: .applicationSupportDirectory) ignores the environment variable — and a
/// suite-less smoke run overwrites the real archive cache with fixture data (observed 2026-07-12).
/// AGENTS.md row "Isolated launches"; docs/user-e2e.md.
final class E2ESmokeIsolationSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Isolated launches",
        why: "A smoke run outside its own suite and exact binary overwrote the person's real archive cache once",
        see: "AGENTS.md row \"Isolated launches\"; docs/user-e2e.md",
        fix: "Launch the built binary by PID with NIKO_MUSIC_HUB_SETTINGS_SUITE, capture only its window, and clean the suite up"
    )

    private static let smoke = "script/e2e_user_smoke.sh"
    private static let probe = "script/ui_probe.swift"

    func testArchiveSmokeRunsInIsolatedSettingsSuite() {
        Self.rule.expect(Self.smoke, contains: [#"export NIKO_MUSIC_HUB_SETTINGS_SUITE="$ARCHIVE_SUITE""#],
                         because: "the app under smoke must not touch the real archive cache")
        Self.rule.expect(Self.smoke, lacks: ["export HOME="], because: "overriding $HOME does not isolate Application Support")
    }

    func testSmokeCleansUpIsolatedSuites() {
        Self.rule.expect(Self.smoke, contains: [#"rm -rf "$ISOLATED_ROOT/$ARCHIVE_SUITE" "$ISOLATED_ROOT/$UI_SUITE""#],
                         because: "smoke runs remove their Isolated/<suite> folders so they do not accumulate")
    }

    func testPublicUILaunchUsesExactBinaryPIDAndIsolatedSuite() {
        Self.rule.expect(Self.smoke, contains: [
            #"NIKO_MUSIC_HUB_SETTINGS_SUITE="$UI_SUITE" \"#, #""$APP_BINARY" >"$PUBLIC_UI_LOG" 2>&1 &"#,
            "PUBLIC_UI_PID=$!", #"--pid "$PUBLIC_UI_PID""#, #"--binary-path "$APP_BINARY""#,
        ])
        Self.rule.expect(Self.smoke, lacks: ["pgrep -x NikoMusicHub"],
                         because: "the newest process can be a normally configured app that exposes the person's archive")
        Self.rule.expect(Self.smoke, lacks: ["./script/build_and_run.sh"],
                         because: "the public UI smoke launches the built binary, not whatever LaunchServices finds")
    }

    func testSmokeForceStopsAppsBeforeAndAfterLaunches() {
        Self.rule.require(
            SourceTree.read(Self.smoke).components(separatedBy: "nmh_stop_app true").count - 1 >= 2,
            "\(Self.smoke) no longer force-stops an old app before the isolated launch and the isolated app at cleanup"
        )
    }

    func testAXDumpIsWindowOnlyAndCannotCollectSystemRecentItems() {
        Self.rule.expect(Self.probe, contains: ["Window-only output avoids collecting unrelated system menu/recent-item data"],
                         lacks: ["dumpAX(app, depth:"])
        Self.rule.expect(Self.smoke, contains: [#"--capture "$PUBLIC_UI_SCREENSHOT""#], lacks: ["screencapture -x"],
                         because: "screenshots target the isolated app window, not the whole desktop")
    }

    func testCheckVisibleRequiresOnScreenWindow() {
        Self.rule.expect(Self.probe, contains: ["guard (window[kCGWindowIsOnscreen as String] as? Bool) == true else { continue }"],
                         because: "--check-visible rejects minimized, ordered-out and other-Space windows that .optionAll lists")
    }

    /// The readiness marker must be copy the first-run view really renders: the 1.6.0 rewording turned
    /// the strict release gate red for a stale string.
    func testPublicUIAccessibilityReadinessIsBoundedAndFailClosed() {
        let readinessMarker = "The app downloads the free tools it needs into its own folder"
        Self.rule.expect(Self.smoke, contains: [
            "PUBLIC_UI_DEADLINE=$((SECONDS + 20))", "grep -Fq \"\(readinessMarker)\"",
            "strict UI mode requires AX-visible first-run content",
        ])
        Self.rule.expect("Sources/NikoMusicHub/Onboarding/HubSetupView.swift", contains: [readinessMarker],
                         because: "e2e_user_smoke.sh waits for this first-run copy")
    }

    func testFullDeveloperCheckRequiresAccessibilityVisibleUI() {
        Self.rule.expect("script/dev.sh", contains: ["env NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh"],
                         because: "a green dev.sh check must not downgrade an inaccessible UI smoke to a window-only result")
    }
}
