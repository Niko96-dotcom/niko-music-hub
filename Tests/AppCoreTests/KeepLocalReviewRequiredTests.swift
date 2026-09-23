@testable import AppCore
import Foundation
import NikoMusicCore
import XCTest

/// Final settings-repair safety finding: a repair that resets the Keep Local
/// list must raise a durable review obligation that refuses every active-copy
/// removal until Review Keep Local clears it — even with Emergency Stop
/// cleared. Copy-only transfers stay allowed. Fixture roots only; never real
/// music archives.
final class KeepLocalReviewRequiredTests: XCTestCase {
    private let key = "nikoMusicHub.settings"
    private var cleanup: [URL] = []

    override func tearDown() {
        for url in cleanup { try? FileManager.default.removeItem(at: url) }
        cleanup = []
        super.tearDown()
    }

    // MARK: - Decode

    func testMissingFlagDecodesFalse() throws {
        let vault = try JSONDecoder().decode(
            VaultSettings.self,
            from: Data(#"{"isEnabled":true}"#.utf8)
        )
        XCTAssertFalse(vault.keepLocalReviewRequired)
        let app = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"vault":{"isEnabled":true}}"#.utf8)
        )
        XCTAssertFalse(app.vault.keepLocalReviewRequired)
        XCTAssertFalse(VaultSettings().keepLocalReviewRequired)
    }

    func testMalformedFlagFailsNormalDecode() throws {
        for junk in [#""yes""#, "1", "null", "[]", "{}"] {
            let vaultPayload = Data(#"{"isEnabled":true,"keepLocalReviewRequired":\#(junk)}"#.utf8)
            XCTAssertThrowsError(
                try JSONDecoder().decode(VaultSettings.self, from: vaultPayload),
                "present malformed review flag must throw: \(junk)"
            )
            let appPayload = Data(#"{"vault":{"isEnabled":true,"keepLocalReviewRequired":\#(junk)}}"#.utf8)
            XCTAssertThrowsError(
                try JSONDecoder().decode(AppSettings.self, from: appPayload),
                "present malformed review flag inside AppSettings must throw: \(junk)"
            )
        }
    }

    // MARK: - Repair

    func testMalformedFlagSalvagesToTrue() throws {
        let (defaults, _) = makeDefaults()
        var vault = permissiveVaultObject()
        vault["keepLocalReviewRequired"] = "yes"
        defaults.set(try JSONSerialization.data(withJSONObject: ["vault": vault]), forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)

        let outcome = try XCTUnwrap(try store.repairStoredSettings(backupDirectory: makeTempDirectory("review-junk")))
        let repaired = try store.loadSettings().vault

        XCTAssertTrue(repaired.keepLocalReviewRequired, "malformed flag must salvage to true (least destructive)")
        XCTAssertTrue(outcome.resetFields.contains("Project Vault Keep Local review"))
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(repaired))
    }

    func testBrokenKeepLocalListSalvageSetsFlag() throws {
        for junk: Any in ["pinned-a", ["pinned-a", 5], ["id": "pinned-a"]] {
            let (defaults, _) = makeDefaults()
            var vault = permissiveVaultObject()
            vault["keepLocalProjectIDs"] = junk
            defaults.set(try JSONSerialization.data(withJSONObject: ["vault": vault]), forKey: key)
            let store = UserDefaultsSettingsStore(userDefaults: defaults)

            let outcome = try XCTUnwrap(try store.repairStoredSettings(backupDirectory: makeTempDirectory("pins")))
            let repaired = try store.loadSettings().vault

            XCTAssertTrue(repaired.keepLocalReviewRequired, "\(junk)")
            XCTAssertTrue(repaired.automationEmergencyStop, "\(junk)")
            XCTAssertEqual(repaired.spaceIntent, .keepCopy, "\(junk)")
            XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(repaired), "\(junk)")
            XCTAssertFalse(ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(repaired), "\(junk)")
            XCTAssertTrue(
                outcome.message.contains("Keep Local list couldn't be read"),
                outcome.message
            )
        }
        // Readable pins inside a partly broken list are kept, and the flag is set.
        let (defaults, _) = makeDefaults()
        var vault = permissiveVaultObject()
        vault["keepLocalProjectIDs"] = ["pinned-a", 5]
        defaults.set(try JSONSerialization.data(withJSONObject: ["vault": vault]), forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        _ = try store.repairStoredSettings(backupDirectory: makeTempDirectory("partial-pins"))
        let repaired = try store.loadSettings().vault
        XCTAssertEqual(repaired.keepLocalProjectIDs, ["pinned-a"])
        XCTAssertTrue(repaired.keepLocalReviewRequired)
    }

    func testUnreadableWholeVaultOrBlobSetsFlag() throws {
        for blob in [Data(#"{"vault":"broken"}"#.utf8), Data("not json at all".utf8)] {
            let (defaults, _) = makeDefaults()
            defaults.set(blob, forKey: key)
            let store = UserDefaultsSettingsStore(userDefaults: defaults)
            let outcome = try XCTUnwrap(try store.repairStoredSettings(backupDirectory: makeTempDirectory("blob")))
            XCTAssertTrue(try store.loadSettings().vault.keepLocalReviewRequired, String(data: blob, encoding: .utf8) ?? "?")
            XCTAssertTrue(outcome.vaultRemovalPaused)
        }
    }

    func testStoredTrueFlagSurvivesUnrelatedRepair() throws {
        let (defaults, _) = makeDefaults()
        var vault = permissiveVaultObject()
        vault["keepLocalReviewRequired"] = true
        vault["spaceIntent"] = "bogus"
        defaults.set(try JSONSerialization.data(withJSONObject: ["vault": vault]), forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)

        _ = try XCTUnwrap(try store.repairStoredSettings(backupDirectory: makeTempDirectory("preserve")))
        let repaired = try store.loadSettings().vault

        XCTAssertTrue(repaired.keepLocalReviewRequired, "a previously true flag must survive repair")
        XCTAssertEqual(repaired.spaceIntent, .keepCopy)
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(repaired))
    }

    // MARK: - Flag is never cleared except by Done Reviewing

    func testClearingEmergencyStopDoesNotClearFlag() throws {
        let fixture = try KeepLocalReviewFixture()
        defer { fixture.cleanup() }
        try fixture.savePermissiveSettings(reviewRequired: true, stop: true)

        try fixture.settingsStore.updateSettings { $0.vault.automationEmergencyStop = false }

        let vault = try fixture.settingsStore.loadSettings().vault
        XCTAssertFalse(vault.automationEmergencyStop)
        XCTAssertTrue(vault.keepLocalReviewRequired, "clearing Emergency Stop must never clear the review flag")
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(vault))
    }

    func testFinishSetupNeverClearsFlag() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/Settings/ProjectVaultSettingsView.swift",
            encoding: .utf8
        )
        guard let start = source.range(of: "private func finishSetup()") else {
            XCTFail("finishSetup not found")
            return
        }
        let rest = source[start.upperBound...]
        guard let end = rest.range(of: "\n    private func ") ?? rest.range(of: "\n    @ViewBuilder") else {
            XCTFail("finishSetup body end not found")
            return
        }
        XCTAssertFalse(
            rest[..<end.lowerBound].contains("keepLocalReviewRequired"),
            "finishSetup must never touch the review flag"
        )
    }

    func testDoneReviewingClearsFlagAndKeepsPinsTogether() throws {
        let (defaults, _) = makeDefaults()
        var vault = permissiveVaultObject()
        vault["keepLocalReviewRequired"] = true
        defaults.set(try JSONSerialization.data(withJSONObject: ["vault": vault]), forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)

        // Same atomic save the Review sheet performs: clear the flag, carry pins.
        let pins = try store.loadSettings().vault.keepLocalProjectIDs
        try store.updateSettings {
            $0.vault.keepLocalReviewRequired = false
            $0.vault.keepLocalProjectIDs = pins
        }
        let cleared = try store.loadSettings().vault
        XCTAssertFalse(cleared.keepLocalReviewRequired)
        XCTAssertEqual(cleared.keepLocalProjectIDs, ["pinned-a", "pinned-b"])
        XCTAssertTrue(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(cleared))
    }

    // MARK: - Review UX follow-up (disabled-Vault visibility, routing, stale pins)

    func testDoneReviewPolicyPreservesConcurrentPins() throws {
        let (defaults, _) = makeDefaults()
        var vault = permissiveVaultObject()
        vault["keepLocalReviewRequired"] = true
        vault["keepLocalProjectIDs"] = ["pinned-a"]
        defaults.set(try JSONSerialization.data(withJSONObject: ["vault": vault]), forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        try seedMatchingEnabledRoots(into: store)

        // A pin added while the review sheet is open (after the sheet's
        // snapshot) must survive Done Reviewing.
        try store.updateSettings { $0.vault.keepLocalProjectIDs.insert("pinned-b") }
        // The fixed Done Reviewing path: clear only the flag against latest storage.
        try store.updateSettings { settings in
            _ = KeepLocalReviewPolicy.completeReview(&settings, confirmed: true, browserVisited: true)
        }

        let cleared = try store.loadSettings().vault
        XCTAssertFalse(cleared.keepLocalReviewRequired)
        XCTAssertEqual(cleared.keepLocalProjectIDs, ["pinned-a", "pinned-b"])
    }

    func testDoneReviewPolicyNeverTouchesPins() throws {
        var settings = configuredReviewSettings()
        settings.vault.keepLocalProjectIDs = ["pinned-a", "pinned-b"]
        XCTAssertTrue(KeepLocalReviewPolicy.completeReview(&settings, confirmed: true, browserVisited: true))
        XCTAssertFalse(settings.vault.keepLocalReviewRequired)
        XCTAssertEqual(settings.vault.keepLocalProjectIDs, ["pinned-a", "pinned-b"])
    }

    func testReviewPolicyRefusesClearanceBeforeBrowserVisit() {
        var settings = configuredReviewSettings()
        XCTAssertFalse(
            KeepLocalReviewPolicy.canCompleteReview(settings, confirmed: true, browserVisited: false),
            "checkbox alone must not suffice"
        )
        XCTAssertFalse(KeepLocalReviewPolicy.canCompleteReview(settings, confirmed: false, browserVisited: true))
        XCTAssertFalse(KeepLocalReviewPolicy.canCompleteReview(settings, confirmed: false, browserVisited: false))

        settings.vault.keepLocalProjectIDs = ["pinned-a"]
        XCTAssertFalse(KeepLocalReviewPolicy.completeReview(&settings, confirmed: true, browserVisited: false))
        XCTAssertTrue(settings.vault.keepLocalReviewRequired, "flag must survive a checkbox-only attempt")
        XCTAssertEqual(settings.vault.keepLocalProjectIDs, ["pinned-a"])
        XCTAssertFalse(KeepLocalReviewPolicy.completeReview(&settings, confirmed: false, browserVisited: true))
        XCTAssertTrue(settings.vault.keepLocalReviewRequired)
    }

    func testReviewPolicyClearsAfterBrowserVisitAndKeepsPins() {
        let settings = configuredReviewSettings()
        XCTAssertTrue(KeepLocalReviewPolicy.canCompleteReview(settings, confirmed: true, browserVisited: true))

        var clearing = settings
        clearing.vault.keepLocalProjectIDs = ["pinned-a", "pinned-b"]
        XCTAssertTrue(KeepLocalReviewPolicy.completeReview(&clearing, confirmed: true, browserVisited: true))
        XCTAssertFalse(clearing.vault.keepLocalReviewRequired)
        XCTAssertEqual(clearing.vault.keepLocalProjectIDs, ["pinned-a", "pinned-b"])
    }

    func testGatedReviewPreservesConcurrentPins() throws {
        let (defaults, _) = makeDefaults()
        var vault = permissiveVaultObject()
        vault["keepLocalReviewRequired"] = true
        vault["keepLocalProjectIDs"] = ["pinned-a"]
        defaults.set(try JSONSerialization.data(withJSONObject: ["vault": vault]), forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        try seedMatchingEnabledRoots(into: store)

        // A pin added while the sheet is open must survive gated Done Reviewing.
        try store.updateSettings { $0.vault.keepLocalProjectIDs.insert("pinned-b") }

        // Checkbox without the browser visit must not clear; the gated policy
        // leaves the flag set.
        try store.updateSettings { settings in
            _ = KeepLocalReviewPolicy.completeReview(&settings, confirmed: true, browserVisited: false)
        }
        XCTAssertTrue(try store.loadSettings().vault.keepLocalReviewRequired)

        // After the visit, the same save clears only the flag and keeps both pins.
        try store.updateSettings { settings in
            _ = KeepLocalReviewPolicy.completeReview(&settings, confirmed: true, browserVisited: true)
        }
        let done = try store.loadSettings().vault
        XCTAssertFalse(done.keepLocalReviewRequired)
        XCTAssertEqual(done.keepLocalProjectIDs, ["pinned-a", "pinned-b"])
    }

    // MARK: - Vault setup gate (empty/unconfigured Vault cannot be reviewed away)

    /// The live finding: with visit + checkbox but Vault off, missing,
    /// mismatched, or disabled roots, Done Reviewing must keep the flag set
    /// and leave pins alone — there were no Vault projects to inspect.
    func testReviewRefusesClearanceWithoutConfiguredVaultRoots() {
        let base = configuredReviewSettings()
        let activeID = base.vault.activeRootID!
        let archiveID = base.vault.archiveRootID!
        let activeRoot = base.musicRoots.first { $0.id == activeID }!
        let archiveRoot = base.musicRoots.first { $0.id == archiveID }!

        var vaultOff = base
        vaultOff.vault.isEnabled = false

        var missingActive = base
        missingActive.vault.activeRootID = nil

        var missingArchive = base
        missingArchive.vault.archiveRootID = nil

        var unknownActive = base
        unknownActive.vault.activeRootID = UUID()

        var unknownArchive = base
        unknownArchive.vault.archiveRootID = UUID()

        var swappedRoles = base
        swappedRoles.vault.activeRootID = archiveID
        swappedRoles.vault.archiveRootID = activeID

        var wrongRoleEntry = base
        wrongRoleEntry.musicRoots = [
            StoredMusicRoot(id: activeID, role: .scanOnly, url: uncreatedRootURL("Active")),
            archiveRoot,
        ]

        var disabledActive = base
        disabledActive.musicRoots = [
            StoredMusicRoot(id: activeID, role: .active, url: uncreatedRootURL("Active"), isEnabled: false),
            archiveRoot,
        ]

        var disabledArchive = base
        disabledArchive.musicRoots = [
            activeRoot,
            StoredMusicRoot(id: archiveID, role: .archive, url: uncreatedRootURL("Archive"), isEnabled: false),
        ]

        var noRoots = base
        noRoots.musicRoots = []

        let cases: [(String, AppSettings)] = [
            ("vault off", vaultOff),
            ("missing Active ID", missingActive),
            ("missing Archive ID", missingArchive),
            ("unknown Active ID", unknownActive),
            ("unknown Archive ID", unknownArchive),
            ("swapped root IDs", swappedRoles),
            ("wrong role entry", wrongRoleEntry),
            ("disabled Active root", disabledActive),
            ("disabled Archive root", disabledArchive),
            ("no stored roots", noRoots),
        ]
        for (name, configured) in cases {
            var settings = configured
            settings.vault.keepLocalReviewRequired = true
            settings.vault.keepLocalProjectIDs = ["pinned-a"]
            XCTAssertFalse(
                KeepLocalReviewPolicy.vaultRootsConfigured(in: settings),
                "\(name) must not count as configured"
            )
            XCTAssertFalse(
                KeepLocalReviewPolicy.canCompleteReview(settings, confirmed: true, browserVisited: true),
                "\(name): visit + checkbox must not clear without configured roots"
            )
            XCTAssertFalse(
                KeepLocalReviewPolicy.completeReview(&settings, confirmed: true, browserVisited: true),
                "\(name): flag must stay set"
            )
            XCTAssertTrue(settings.vault.keepLocalReviewRequired, name)
            XCTAssertEqual(settings.vault.keepLocalProjectIDs, ["pinned-a"], "\(name): pins must survive refusal")
        }
    }

    /// Matching enabled roots of the right roles permit clearance; the
    /// refused cases above prove the same visit + checkbox is not enough alone.
    func testReviewClearsOnlyWithMatchingEnabledRoots() {
        var settings = configuredReviewSettings()
        settings.vault.keepLocalProjectIDs = ["pinned-a"]
        XCTAssertTrue(KeepLocalReviewPolicy.vaultRootsConfigured(in: settings))
        XCTAssertTrue(
            KeepLocalReviewPolicy.canCompleteReview(settings, confirmed: true, browserVisited: true)
        )
        XCTAssertTrue(KeepLocalReviewPolicy.completeReview(&settings, confirmed: true, browserVisited: true))
        XCTAssertFalse(settings.vault.keepLocalReviewRequired)
        XCTAssertEqual(settings.vault.keepLocalProjectIDs, ["pinned-a"])
    }

    /// A visit before choosing a new root must not authorize the new root.
    /// The view discards the recorded visit on any enablement/root change, so
    /// after re-pointing Vault the review needs a fresh browser visit even
    /// though the new roots are fully configured.
    func testChangingRootsRequiresFreshBrowserVisit() {
        var settings = configuredReviewSettings()
        settings.vault.keepLocalProjectIDs = ["pinned-a"]
        XCTAssertTrue(KeepLocalReviewPolicy.completeReview(&settings, confirmed: true, browserVisited: true))
        XCTAssertFalse(settings.vault.keepLocalReviewRequired)

        // A fresh repair re-raises the obligation; the user then picks new
        // folders (both configured and enabled). The stale visit is gone —
        // the view reset leaves browserVisited false — so clearance refuses.
        let newActiveID = UUID()
        let newArchiveID = UUID()
        settings.vault.keepLocalReviewRequired = true
        settings.vault.activeRootID = newActiveID
        settings.vault.archiveRootID = newArchiveID
        settings.musicRoots = [
            StoredMusicRoot(id: newActiveID, role: .active, url: uncreatedRootURL("Active-2")),
            StoredMusicRoot(id: newArchiveID, role: .archive, url: uncreatedRootURL("Archive-2")),
        ]
        XCTAssertTrue(KeepLocalReviewPolicy.vaultRootsConfigured(in: settings))
        XCTAssertFalse(
            KeepLocalReviewPolicy.completeReview(&settings, confirmed: true, browserVisited: false),
            "a pre-change visit must not authorize the new roots"
        )
        XCTAssertTrue(settings.vault.keepLocalReviewRequired)

        // A fresh visit of the new roots clears, keeping pins added meanwhile.
        settings.vault.keepLocalProjectIDs.insert("pinned-b")
        XCTAssertTrue(KeepLocalReviewPolicy.completeReview(&settings, confirmed: true, browserVisited: true))
        XCTAssertFalse(settings.vault.keepLocalReviewRequired)
        XCTAssertEqual(settings.vault.keepLocalProjectIDs, ["pinned-a", "pinned-b"])
    }

    /// A cleared obligation stays cleared only when nothing changed: an
    /// already-false flag is a no-op, so the view must not show success.
    func testReviewCompleteIsNoOpWhenFlagAlreadyClear() {
        var settings = configuredReviewSettings(reviewRequired: false)
        XCTAssertFalse(
            KeepLocalReviewPolicy.canCompleteReview(settings, confirmed: true, browserVisited: true)
        )
        XCTAssertFalse(KeepLocalReviewPolicy.completeReview(&settings, confirmed: true, browserVisited: true))
    }

    // MARK: - Runtime gates

    func testRemovalCaptureRefusedForManualAndDoneWhileReviewRequired() async throws {
        let fixture = try KeepLocalReviewFixture()
        defer { fixture.cleanup() }
        try fixture.savePermissiveSettings(reviewRequired: true, stop: false)
        let runtime = try fixture.runtime()

        do {
            _ = try await runtime.captureArchiveAuthorization(
                for: fixture.song,
                trigger: .manual,
                removingActiveCopy: true,
                catalogProjectID: nil
            )
            XCTFail("manual removal capture must refuse while review is required")
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .keepLocalReviewRequired)
        }
        do {
            _ = try await runtime.captureArchiveAuthorization(
                for: fixture.song,
                trigger: .workflowDone,
                removingActiveCopy: true,
                catalogProjectID: nil
            )
            XCTFail("Done removal capture must refuse while review is required")
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .keepLocalReviewRequired)
        }

        let vault = try fixture.settingsStore.loadSettings().vault
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(vault))
        XCTAssertFalse(ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(vault))
        XCTAssertTrue(ProjectVaultRolloutPolicy.permitsUserInitiatedArchiving(vault), "copy-only archiving stays allowed")
    }

    func testStaleRemovalTokenCannotBypassLiveReviewFlag() async throws {
        let fixture = try KeepLocalReviewFixture()
        defer { fixture.cleanup() }
        try fixture.savePermissiveSettings(reviewRequired: false, stop: false)
        let runtime = try fixture.runtime()
        // Capture before the repair…
        let stale = try await runtime.captureArchiveAuthorization(
            for: fixture.song,
            trigger: .manual,
            removingActiveCopy: true,
            catalogProjectID: nil
        )
        XCTAssertTrue(stale.permitsRemoval)
        // …then the repair raises the flag (Emergency Stop stays cleared).
        try fixture.settingsStore.updateSettings { $0.vault.keepLocalReviewRequired = true }

        do {
            _ = try await runtime.archive(song: fixture.song, trigger: .manual, authorization: stale)
            XCTFail("a pre-repair removal token must not bypass the live review flag")
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .keepLocalReviewRequired)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.project.path),
            "the Active copy must be retained"
        )
    }

    func testCopyOnlyArchiveProceedsWhileReviewRequired() async throws {
        let fixture = try KeepLocalReviewFixture()
        defer { fixture.cleanup() }
        try fixture.savePermissiveSettings(reviewRequired: true, stop: false)
        let runtime = try fixture.runtime()

        let copy = try await runtime.captureArchiveAuthorization(
            for: fixture.song,
            trigger: .manual,
            removingActiveCopy: false,
            catalogProjectID: nil
        )
        let snapshot = try await runtime.archive(song: fixture.song, trigger: .manual, authorization: copy)
        XCTAssertNotNil(snapshot.transfer)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))

        let doneCopy = try await runtime.captureArchiveAuthorization(
            for: fixture.song,
            trigger: .workflowDone,
            removingActiveCopy: false,
            catalogProjectID: nil
        )
        _ = try await runtime.archive(song: fixture.song, trigger: .workflowDone, authorization: doneCopy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testDoneRemovalRefusedAtExecutionWhileReviewRequired() async throws {
        let fixture = try KeepLocalReviewFixture()
        defer { fixture.cleanup() }
        try fixture.savePermissiveSettings(reviewRequired: false, stop: false)
        let runtime = try fixture.runtime()
        let stale = try await runtime.captureArchiveAuthorization(
            for: fixture.song,
            trigger: .workflowDone,
            removingActiveCopy: true,
            catalogProjectID: nil
        )
        try fixture.settingsStore.updateSettings { $0.vault.keepLocalReviewRequired = true }

        do {
            _ = try await runtime.archive(song: fixture.song, trigger: .workflowDone, authorization: stale)
            XCTFail("Done removal must refuse while review is required")
        } catch {
            // Either the direct review error or its scheduler wrapper: the
            // Active copy must be retained in both cases.
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        }
    }

    func testNormalRemovalRulesReturnAfterReviewCleared() async throws {
        let fixture = try KeepLocalReviewFixture()
        defer { fixture.cleanup() }
        try fixture.savePermissiveSettings(reviewRequired: true, stop: false)
        let runtime = try fixture.runtime()

        // Done Reviewing: one save clears the flag and keeps the pins.
        try fixture.settingsStore.updateSettings { $0.vault.keepLocalReviewRequired = false }
        XCTAssertTrue(
            ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(try fixture.settingsStore.loadSettings().vault)
        )

        let removal = try await runtime.captureArchiveAuthorization(
            for: fixture.song,
            trigger: .manual,
            removingActiveCopy: true,
            catalogProjectID: nil
        )
        XCTAssertTrue(removal.permitsRemoval)
        _ = try await runtime.archive(song: fixture.song, trigger: .manual, authorization: removal)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.project.path),
            "normal removal rules return after Done Reviewing"
        )
    }

    // MARK: - Helpers

    /// In-memory settings with a pending review and a fully configured Vault:
    /// enabled, both root IDs present as enabled stored roots of the matching
    /// roles. Root URLs are never created on disk — the policy checks
    /// identity/role/enablement only, and no test touches real archives.
    private func configuredReviewSettings(reviewRequired: Bool = true) -> AppSettings {
        let activeID = UUID()
        let archiveID = UUID()
        var settings = AppSettings.default
        settings.musicRoots = [
            StoredMusicRoot(id: activeID, role: .active, url: uncreatedRootURL("Active")),
            StoredMusicRoot(id: archiveID, role: .archive, url: uncreatedRootURL("Archive")),
        ]
        settings.vault = VaultSettings(
            isEnabled: true,
            activeRootID: activeID,
            archiveRootID: archiveID,
            keepLocalReviewRequired: reviewRequired
        )
        return settings
    }

    private func uncreatedRootURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-keep-local-review-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    /// Raw-JSON seeded stores carry random vault root IDs with no stored
    /// roots; attach matching enabled roots so policy tests exercise the
    /// review gate rather than setup absence.
    private func seedMatchingEnabledRoots(into store: UserDefaultsSettingsStore) throws {
        let seeded = try store.loadSettings()
        let activeID = try XCTUnwrap(seeded.vault.activeRootID)
        let archiveID = try XCTUnwrap(seeded.vault.archiveRootID)
        let activeURL = uncreatedRootURL("Active")
        let archiveURL = uncreatedRootURL("Archive")
        try store.updateSettings { settings in
            settings.musicRoots = [
                StoredMusicRoot(id: activeID, role: .active, url: activeURL),
                StoredMusicRoot(id: archiveID, role: .archive, url: archiveURL),
            ]
        }
    }

    private func permissiveVaultObject() -> [String: Any] {
        [
            "isEnabled": true,
            "activeRootID": UUID().uuidString,
            "archiveRootID": UUID().uuidString,
            "automaticArchiving": true,
            "inactivityDays": 30,
            "minimumFreeSpaceGiB": 120,
            "transferFreeSpaceReserveGiB": 5,
            "keepPreviousGenerationDays": 30,
            "launchAtLogin": true,
            "rolloutStage": "friends",
            "spaceIntent": "freeSpace",
            "automationEmergencyStop": false,
            "independentBackupConfirmed": true,
            "keepLocalProjectIDs": ["pinned-a", "pinned-b"],
        ]
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "KeepLocalReviewRequiredTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func makeTempDirectory(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-keep-local-review-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        cleanup.append(url)
        return url
    }
}

// MARK: - Disposable fixture (temp Active/Archive roots only)

private final class KeepLocalReviewFixture {
    let root: URL
    let active: URL
    let archive: URL
    let project: URL
    let database: SQLiteArchiveDatabase
    let settingsStore: UserDefaultsSettingsStore
    let activeID = UUID()
    let archiveID = UUID()
    let suite: String

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keep-local-review-\(UUID().uuidString)", isDirectory: true)
        active = root.appendingPathComponent("Active", isDirectory: true)
        archive = root.appendingPathComponent("Archive", isDirectory: true)
        project = active.appendingPathComponent("Review Song", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let cpr = project.appendingPathComponent("Review Song.cpr")
        try Data("review-cpr".utf8).write(to: cpr)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: cpr.path)
        database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("vault.sqlite"))
        suite = "KeepLocalReviewRequiredTests.\(UUID().uuidString)"
        settingsStore = UserDefaultsSettingsStore(userDefaults: UserDefaults(suiteName: suite)!)
    }

    var song: Song {
        let cpr = project.appendingPathComponent("Review Song.cpr")
        let version = ProjectVersion(
            filePath: cpr,
            fileName: cpr.lastPathComponent,
            modifiedAt: Date(timeIntervalSince1970: 1)
        )
        return Song(
            folderPath: project,
            originalFolderName: project.lastPathComponent,
            displayTitle: "Review Song",
            projectVersions: [version],
            latestCPR: version,
            workflowStatus: .done
        )
    }

    func savePermissiveSettings(reviewRequired: Bool, stop: Bool) throws {
        var settings = AppSettings.default
        settings.musicRoots = [
            StoredMusicRoot(id: activeID, role: .active, url: active),
            StoredMusicRoot(id: archiveID, role: .archive, url: archive),
        ]
        var vault = VaultSettings(
            isEnabled: true,
            activeRootID: activeID,
            archiveRootID: archiveID,
            automaticArchiving: true,
            automationEmergencyStop: stop,
            independentBackupConfirmed: true,
            keepLocalReviewRequired: reviewRequired
        )
        vault.setSpaceIntent(.freeSpace)
        settings.vault = vault
        try settingsStore.saveSettings(settings)
    }

    func runtime() throws -> LiveProjectVaultRuntime {
        try LiveProjectVaultRuntime(
            settingsStore: settingsStore,
            transferStore: SQLiteVaultTransferStore(database: database),
            catalogStore: SQLiteProjectCatalogStore(database: database),
            projectOpener: SafeVaultProjectOpener(),
            activityProbe: KeepLocalReviewClearProbe(),
            capacityProbe: KeepLocalReviewCapacityProbe(),
            archiveProviderFactory: { LocalFolderArchiveStorage(root: $0) }
        )
    }

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private struct KeepLocalReviewClearProbe: VaultAutomationActivityProbing {
    func cubaseStatus() async -> VaultActivityStatus { .clear }
    func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { .clear }
    func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus { .clear }
}

private struct KeepLocalReviewCapacityProbe: ProjectVaultCapacityProbing {
    func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot {
        ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: 500 * 1_073_741_824,
            archiveAvailableCapacityBytes: 500 * 1_073_741_824,
            projectedArchiveBytes: 1_073_741_824
        )
    }
}
