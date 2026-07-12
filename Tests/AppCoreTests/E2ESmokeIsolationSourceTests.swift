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

    private func smokeScriptSource() throws -> String {
        let path = "script/e2e_user_smoke.sh"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Script not found relative to cwd — run tests from repo root")
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}
