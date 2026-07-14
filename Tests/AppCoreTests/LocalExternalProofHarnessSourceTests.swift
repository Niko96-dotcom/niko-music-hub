import XCTest

final class LocalExternalProofHarnessSourceTests: XCTestCase {
    func testLocalInstallUsesDirtyAwareIdentityAndExactInstalledHashVerification() throws {
        let install = try SourceTestSupport.read("script/install-local.sh")
        XCTAssertTrue(install.contains("local-build-identity.sh"))
        XCTAssertTrue(install.contains("NMH_EXPECTED_BUILD_ID"))
        XCTAssertTrue(install.contains("NMH_EXPECTED_BINARY_SHA256"))
        XCTAssertTrue(install.contains("codesign --verify --deep --strict"))

        let identity = try SourceTestSupport.read("script/local-build-identity.sh")
        XCTAssertTrue(identity.contains("--cached --others --exclude-standard"))
        XCTAssertTrue(identity.contains(".dirty."))
        XCTAssertTrue(identity.contains("Sources"))
    }

    func testBookmarkProofUsesTwoExactBinaryProcessesAndAnIsolatedSuite() throws {
        let proof = try SourceTestSupport.read("script/prove-bookmark-relaunch.sh")
        XCTAssertTrue(proof.contains("NIKO_MUSIC_HUB_SETTINGS_SUITE"))
        XCTAssertTrue(proof.contains("run_proof_process seed"))
        XCTAssertTrue(proof.contains("run_proof_process verify"))
        XCTAssertTrue(proof.contains(#""$APP_BINARY" >"$log" 2>&1"#))
        XCTAssertTrue(proof.contains(#"defaults delete "$SUITE""#))
        XCTAssertFalse(proof.contains("/usr/bin/open"))
        XCTAssertFalse(proof.contains("pgrep"))
    }
}
