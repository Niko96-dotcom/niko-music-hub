import XCTest

/// The local install and the bookmark relaunch proof run the exact binary they built, in an isolated
/// settings suite. AGENTS.md row "Isolated launches"; docs/local-dev-flow.md.
final class LocalExternalProofHarnessSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Proof harnesses run the exact binary",
        why: "A proof that launches through LaunchServices or picks a process by name can test another build or the person's own app",
        see: "AGENTS.md row \"Isolated launches\"; docs/local-dev-flow.md",
        fix: "Launch the built binary directly with an isolated suite and verify its build ID and hash"
    )

    func testLocalInstallUsesDirtyAwareIdentityAndExactInstalledHashVerification() {
        Self.rule.expect("script/install-local.sh", contains: [
            "local-build-identity.sh", "NMH_EXPECTED_BUILD_ID", "NMH_EXPECTED_BINARY_SHA256", "codesign --verify --deep --strict",
        ])
        Self.rule.expect("script/local-build-identity.sh", contains: ["--cached --others --exclude-standard", ".dirty.", "Sources"])
    }

    func testBookmarkProofUsesTwoExactBinaryProcessesAndAnIsolatedSuite() {
        Self.rule.expect(
            "script/prove-bookmark-relaunch.sh",
            contains: [
                "NIKO_MUSIC_HUB_SETTINGS_SUITE", "run_proof_process seed", "run_proof_process verify",
                #""$APP_BINARY" >"$log" 2>&1"#, #"nmh_prepare_isolated_app "$SUITE" "$APP_PATH""#,
                #"APP_BINARY="$NMH_ISOLATED_APP_BINARY""#, #"nmh_forget_settings_suite "$SUITE""#,
            ],
            lacks: ["/usr/bin/open", "pgrep"]
        )
    }
}
