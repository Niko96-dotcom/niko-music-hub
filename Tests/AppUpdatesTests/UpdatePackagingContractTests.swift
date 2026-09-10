import XCTest

/// Source-level guards for the parts of the update path that live in shell and
/// therefore cannot be unit tested directly. Each assertion stands for a failure
/// that would only surface after a release had already shipped.
final class UpdatePackagingContractTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    /// Shell comments explain what the script deliberately avoids, so a naive
    /// substring search would flag the explanation as the violation it warns about.
    private func executableSource(_ path: String) throws -> String {
        try source(path)
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
    }

    /// The executable links @rpath/Sparkle.framework and SPM leaves only
    /// @loader_path on it, so the bundle needs both the embedded framework and
    /// the added rpath or it dies in dyld at launch.
    func testBundleEmbedsSparkleAndAddsItsRunpath() throws {
        let lifecycle = try source("script/lib/app_lifecycle.sh")

        XCTAssertTrue(lifecycle.contains("nmh_embed_sparkle_framework"))
        XCTAssertTrue(lifecycle.contains("NMH_APP_FRAMEWORKS=\"$NMH_APP_CONTENTS/Frameworks\""))
        XCTAssertTrue(lifecycle.contains("install_name_tool -add_rpath \"@executable_path/../Frameworks\""))
        XCTAssertTrue(
            lifecycle.contains("/usr/bin/ditto \"$source_framework\" \"$NMH_SPARKLE_FRAMEWORK\""),
            "the framework must be copied with ditto so its version symlinks survive"
        )
    }

    /// `codesign --deep` is deprecated for signing and would stamp the app's own
    /// entitlements onto Sparkle's updater and installer helpers.
    func testBundleIsSignedInsideOutRatherThanWithDeep() throws {
        let lifecycle = try executableSource("script/lib/app_lifecycle.sh")

        XCTAssertFalse(
            lifecycle.contains("--deep"),
            "nested Sparkle code must be signed individually, not with codesign --deep"
        )
        for nested in ["XPCServices/", "Updater.app", "Autoupdate", "Versions/B"] {
            XCTAssertTrue(
                lifecycle.contains(nested),
                "inside-out signing must cover \(nested)"
            )
        }
    }

    /// A stray file directly under Contents/ is treated by codesign as unsigned
    /// nested code and breaks sealing, so the entitlements input stays outside
    /// the shipped bundle.
    func testEntitlementsInputIsNotShippedInsideTheBundle() throws {
        let lifecycle = try source("script/lib/app_lifecycle.sh")

        XCTAssertTrue(lifecycle.contains("NMH_ENTITLEMENTS_PLIST=\"$NMH_DIST_DIR/NikoMusicHub.entitlements\""))
        XCTAssertFalse(lifecycle.contains("NMH_ENTITLEMENTS_PLIST=\"$NMH_APP_CONTENTS/"))
    }

    /// Both halves of the fail-closed rule: no key means no feed URL, and a
    /// debug build stays inert unless a test feed is named explicitly.
    func testUpdateKeysAreGatedFailClosed() throws {
        let lifecycle = try source("script/lib/app_lifecycle.sh")

        XCTAssertTrue(lifecycle.contains("nmh_resolve_update_configuration"))
        XCTAssertTrue(lifecycle.contains("disabled: no SPARKLE_PUBLIC_ED_KEY"))
        XCTAssertTrue(
            lifecycle.contains("[[ \"$NMH_BUILD_CONFIGURATION\" != \"release\" && -z \"${NMH_UPDATE_FEED_URL:-}\" ]]"),
            "debug bundles must not ship a live feed unless one is named explicitly"
        )
    }

    /// SURequireSignedFeed does nothing without SUVerifyUpdateBeforeExtraction,
    /// so the pair must be emitted together.
    func testSignedFeedKeysShipTogether() throws {
        let lifecycle = try source("script/lib/app_lifecycle.sh")

        for key in [
            "SUFeedURL",
            "SUPublicEDKey",
            "SUEnableAutomaticChecks",
            "SUScheduledCheckInterval",
            "SUVerifyUpdateBeforeExtraction",
            "SURequireSignedFeed",
        ] {
            XCTAssertTrue(lifecycle.contains("<key>\(key)</key>"), "Info.plist is missing \(key)")
        }
    }

    /// The feed URL is compiled into every shipped build, so it may only be
    /// defined in one place and must be HTTPS.
    func testFeedURLContractLivesInOnePlace() throws {
        let env = try source("script/release-env.sh")

        XCTAssertTrue(env.contains("nmh_update_feed_url"))
        XCTAssertTrue(env.contains("nmh_release_repository_url"))
        XCTAssertTrue(env.contains("releases/latest/download/appcast.xml"))
        XCTAssertTrue(
            env.contains("update feed URL must be HTTPS"),
            "a non-HTTPS feed must be refused outright"
        )
    }

    /// SUFeedURL points at releases/latest/download/appcast.xml, so the asset has
    /// to be published under exactly that basename, verified where it landed,
    /// and required in public mode.
    func testReleasePublishesAndVerifiesTheFeed() throws {
        let release = try source("script/release-all.sh")

        XCTAssertTrue(release.contains("APPCAST=\"$RELEASE_DIR/appcast.xml\""))
        XCTAssertTrue(release.contains("generate_update_feed"))
        XCTAssertTrue(release.contains("validate-update-feed.py"))
        XCTAssertTrue(release.contains("validate-hosted-update-feed"))
        XCTAssertTrue(
            release.contains("public release requires SPARKLE_PUBLIC_ED_KEY"),
            "a public release without a feed silently strands every installed app"
        )
        XCTAssertTrue(
            release.contains("\"$RELEASE_NOTES\" \"$APPCAST\" --verify-tag"),
            "the appcast must be part of the published asset set"
        )
    }

    /// The enclosure signature covers the exact published bytes, so the feed can
    /// only be generated once the DMG is signed, notarized and stapled.
    func testFeedIsGeneratedAfterTheArtifactIsFinal() throws {
        let release = try source("script/release-all.sh")

        let staple = try XCTUnwrap(release.range(of: "run staple-dmg"))
        let checksums = try XCTUnwrap(release.range(of: "log \"checksums and manifest\""))
        let feed = try XCTUnwrap(release.range(of: "log \"update feed\""))
        let publication = try XCTUnwrap(release.range(of: "log \"publication\""))

        XCTAssertTrue(staple.lowerBound < checksums.lowerBound)
        XCTAssertTrue(checksums.lowerBound < feed.lowerBound)
        XCTAssertTrue(feed.lowerBound < publication.lowerBound)
    }

    /// The validator's whole reason to exist: proving the key inside the app we
    /// are about to publish is the key that signed the feed.
    func testFeedValidatorChecksTheEmbeddedKeyAndBothSignatures() throws {
        let validator = try source("script/validate-update-feed.py")

        XCTAssertTrue(validator.contains("SUPublicEDKey"))
        XCTAssertTrue(validator.contains("sparkle:edSignature"))
        XCTAssertTrue(validator.contains("sparkle-signatures"))
        XCTAssertTrue(validator.contains("SURequireSignedFeed"))
        XCTAssertTrue(validator.contains("SUVerifyUpdateBeforeExtraction"))
        XCTAssertTrue(
            validator.contains("unverified feed"),
            "a missing crypto backend must fail the release, not skip the check"
        )
    }

    /// The manual check must stay in the app menu. It lives in the same group
    /// that replaces .appInfo, so a second `CommandGroup` anchored at that
    /// placement is the easy way to lose it.
    func testCheckForUpdatesIsInTheAppMenu() throws {
        let menu = try source("Sources/NikoMusicHub/AppMenu.swift")

        XCTAssertTrue(menu.contains("CommandGroup(replacing: .appInfo)"))
        XCTAssertTrue(menu.contains("AppUpdateCheckButton(controller: updateController)"))
        XCTAssertEqual(
            menu.components(separatedBy: "CommandGroup(").count - 1,
            1,
            "About and Check for Updates belong in one group at the .appInfo placement"
        )

        let button = try source("Sources/AppUpdates/AppUpdateCheckButton.swift")
        XCTAssertTrue(button.contains("Check for Updates…"))
        XCTAssertTrue(
            button.contains("controller.checkForUpdates()"),
            "the menu item must actually start a check"
        )
    }

    /// Sparkle is pinned exactly and kept out of AppCore and the feature modules.
    func testSparkleIsPinnedAndIsolatedToTheUpdatesModule() throws {
        let package = try source("Package.swift")

        XCTAssertTrue(package.contains("exact: \"2.9.6\""), "Sparkle must be pinned to an exact version")
        XCTAssertTrue(package.contains("name: \"AppUpdates\""))

        let appCoreTarget = try XCTUnwrap(package.range(of: """
                .target(
                    name: "AppCore",
                    dependencies: ["NikoMusicCore"]
                ),
        """.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertFalse(
            package[appCoreTarget].contains("Sparkle"),
            "AppCore must not link Sparkle"
        )
    }

    /// Nothing outside the updates module may reach for Sparkle directly.
    func testOnlyTheUpdatesModuleImportsSparkle() throws {
        let root = "Sources"
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: root))
        for case let item as String in enumerator where item.hasSuffix(".swift") {
            guard !item.hasPrefix("AppUpdates/") else { continue }
            let contents = try source("\(root)/\(item)")
            XCTAssertFalse(
                contents.contains("import Sparkle"),
                "\(item) imports Sparkle directly; go through AppUpdates instead"
            )
        }
    }
}
