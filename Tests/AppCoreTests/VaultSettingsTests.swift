import AppCore
import Foundation
import NikoMusicCore
import XCTest

final class VaultSettingsTests: XCTestCase {
    func testVaultDefaultsAreOptInAndMatchPolicy() {
        let vault = AppSettings.default.vault
        XCTAssertFalse(vault.isEnabled)
        XCTAssertNil(vault.activeRootID)
        XCTAssertNil(vault.archiveRootID)
        XCTAssertFalse(vault.automaticArchiving, "background inactivity/disk-pressure scheduling is independent opt-in")
        XCTAssertEqual(vault.inactivityDays, 30)
        XCTAssertEqual(vault.minimumFreeSpaceGiB, 120)
        XCTAssertEqual(vault.transferFreeSpaceReserveGiB, 5)
        XCTAssertEqual(vault.keepPreviousGenerationDays, 30)
        XCTAssertTrue(vault.launchAtLogin)
        XCTAssertEqual(vault.spaceIntent, .keepCopy)
        XCTAssertEqual(vault.rolloutStage, .disabled)
    }

    func testSpaceIntentMigratesFromLegacyRollout() throws {
        let disabled = try JSONDecoder().decode(VaultSettings.self, from: Data(#"{"isEnabled":false,"rolloutStage":"disabled"}"#.utf8))
        XCTAssertEqual(disabled.spaceIntent, .keepCopy)
        XCTAssertEqual(disabled.rolloutStage, .disabled)
        XCTAssertFalse(disabled.isEnabled)

        let beta = try JSONDecoder().decode(VaultSettings.self, from: Data(#"{"isEnabled":true,"rolloutStage":"privateBeta"}"#.utf8))
        XCTAssertEqual(beta.spaceIntent, .keepCopy)
        XCTAssertEqual(beta.rolloutStage, .privateBeta)

        let friends = try JSONDecoder().decode(VaultSettings.self, from: Data(#"{"isEnabled":true,"rolloutStage":"friends","independentBackupConfirmed":true}"#.utf8))
        XCTAssertEqual(friends.spaceIntent, .freeSpace)
        XCTAssertEqual(friends.rolloutStage, .friends)

        let missing = try JSONDecoder().decode(VaultSettings.self, from: Data(#"{"isEnabled":true}"#.utf8))
        XCTAssertEqual(missing.spaceIntent, .keepCopy)
        XCTAssertEqual(missing.rolloutStage, .disabled)

        let empty = try JSONDecoder().decode(VaultSettings.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(empty.spaceIntent, .keepCopy)
        XCTAssertFalse(empty.isEnabled)
    }

    func testAppSettingsVaultMigratesFriendsToFreeSpace() throws {
        let data = Data(#"{"vault":{"isEnabled":true,"rolloutStage":"friends","independentBackupConfirmed":true}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.vault.spaceIntent, .freeSpace)
        XCTAssertEqual(settings.vault.rolloutStage, .friends)
        XCTAssertTrue(settings.vault.isEnabled)
    }

    func testExplicitSpaceIntentWinsOverLegacyRollout() throws {
        let kept = try JSONDecoder().decode(
            VaultSettings.self,
            from: Data(#"{"isEnabled":true,"rolloutStage":"friends","spaceIntent":"keepCopy"}"#.utf8)
        )
        XCTAssertEqual(kept.spaceIntent, .keepCopy)
        XCTAssertEqual(kept.rolloutStage, .friends)

        let freed = try JSONDecoder().decode(
            VaultSettings.self,
            from: Data(#"{"isEnabled":true,"rolloutStage":"privateBeta","spaceIntent":"freeSpace"}"#.utf8)
        )
        XCTAssertEqual(freed.spaceIntent, .freeSpace)
        XCTAssertEqual(freed.rolloutStage, .privateBeta)

        let roundTripped = try JSONDecoder().decode(VaultSettings.self, from: JSONEncoder().encode(freed))
        XCTAssertEqual(roundTripped.spaceIntent, .freeSpace)
        XCTAssertEqual(roundTripped.rolloutStage, .privateBeta)
    }

    func testCorruptSpaceIntentFailsClosedRatherThanInferringFreeSpace() throws {
        for payload in [
            #"{"isEnabled":true,"rolloutStage":"friends","spaceIntent":"bogus"}"#,
            #"{"isEnabled":true,"rolloutStage":"friends","spaceIntent":123}"#,
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(VaultSettings.self, from: Data(payload.utf8)),
                "a present but invalid intent must throw instead of inferring free space"
            )
        }

        let wrapped = Data(#"{"vault":{"isEnabled":true,"rolloutStage":"friends","spaceIntent":"bogus","independentBackupConfirmed":true}}"#.utf8)
        let fallback = try JSONDecoder().decode(AppSettings.self, from: wrapped)
        XCTAssertEqual(fallback.vault.spaceIntent, .keepCopy, "corrupt intent must never decode to free space")
        XCTAssertFalse(ProjectVaultRolloutPolicy.expressesFreeSpaceIntent(fallback.vault))
    }

    func testExplicitNullSpaceIntentFailsClosedRatherThanMigrating() throws {
        // An explicit null is a present invalid value, not a missing key: it
        // must never migrate `friends` to free space.
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                VaultSettings.self,
                from: Data(#"{"isEnabled":true,"rolloutStage":"friends","spaceIntent":null}"#.utf8)
            ),
            "an explicit null intent must throw instead of inferring free space"
        )

        let wrapped = Data(#"{"vault":{"isEnabled":true,"rolloutStage":"friends","spaceIntent":null,"independentBackupConfirmed":true}}"#.utf8)
        let fallback = try JSONDecoder().decode(AppSettings.self, from: wrapped)
        XCTAssertEqual(fallback.vault.spaceIntent, .keepCopy, "explicit null must never decode to free space")
        XCTAssertFalse(ProjectVaultRolloutPolicy.expressesFreeSpaceIntent(fallback.vault))
    }

    func testSetSpaceIntentSyncsLegacyRolloutWithoutEnablingDisabled() {
        var disabled = VaultSettings(isEnabled: false, rolloutStage: .disabled)
        XCTAssertEqual(disabled.spaceIntent, .keepCopy)
        disabled.setSpaceIntent(.keepCopy)
        XCTAssertEqual(disabled.rolloutStage, .disabled, "choosing Keep must never flip a stored disabled on")

        var beta = VaultSettings(isEnabled: true, rolloutStage: .privateBeta)
        beta.setSpaceIntent(.freeSpace)
        XCTAssertEqual(beta.spaceIntent, .freeSpace)
        XCTAssertEqual(beta.rolloutStage, .friends)

        var friends = VaultSettings(isEnabled: true, rolloutStage: .friends, spaceIntent: .freeSpace)
        friends.setSpaceIntent(.keepCopy)
        XCTAssertEqual(friends.spaceIntent, .keepCopy)
        XCTAssertEqual(friends.rolloutStage, .privateBeta, "downgrading to Keep steps friends back to copy-only")
    }

    func testAutomaticArchivingMissingDecodesOffButExplicitTruePreserved() throws {
        let missing = try JSONDecoder().decode(VaultSettings.self, from: Data(#"{"isEnabled":true}"#.utf8))
        XCTAssertFalse(missing.automaticArchiving, "missing background-scheduling key must default off")

        let empty = try JSONDecoder().decode(VaultSettings.self, from: Data(#"{}"#.utf8))
        XCTAssertFalse(empty.automaticArchiving)

        let explicitOn = try JSONDecoder().decode(
            VaultSettings.self,
            from: Data(#"{"isEnabled":true,"automaticArchiving":true}"#.utf8)
        )
        XCTAssertTrue(explicitOn.automaticArchiving, "explicit legacy true must be preserved")

        let explicitOff = try JSONDecoder().decode(
            VaultSettings.self,
            from: Data(#"{"isEnabled":true,"automaticArchiving":false}"#.utf8)
        )
        XCTAssertFalse(explicitOff.automaticArchiving)

        XCTAssertFalse(VaultSettings().automaticArchiving)
        XCTAssertFalse(AppSettings.default.vault.automaticArchiving)
    }

    func testLegacyPressureThresholdDecodesIndependentlyOfTransferReserve() throws {
        let legacy = Data(#"{"isEnabled":true,"minimumFreeSpaceGiB":120}"#.utf8)
        var settings = try JSONDecoder().decode(VaultSettings.self, from: legacy)
        XCTAssertEqual(settings.minimumFreeSpaceGiB, 120)
        XCTAssertEqual(settings.transferFreeSpaceReserveGiB, 5)
        settings.transferFreeSpaceReserveGiB = 12
        let restored = try JSONDecoder().decode(VaultSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.minimumFreeSpaceGiB, 120)
        XCTAssertEqual(restored.transferFreeSpaceReserveGiB, 12)
    }

    func testLegacyRootsMigrateToScanOnlyAndPersistTypedIdentity() throws {
        let defaults = try makeDefaults()
        let legacy = #"{"archiveRoots":[{"path":"/tmp/legacy-one"},{"path":"/tmp/legacy-two"}]}"#
        defaults.set(Data(legacy.utf8), forKey: "nikoMusicHub.settings")
        let store = UserDefaultsSettingsStore(userDefaults: defaults)

        let loaded = try store.loadSettings()
        XCTAssertEqual(loaded.musicRoots.map(\.role), [.scanOnly, .scanOnly])
        XCTAssertEqual(loaded.musicRoots.map(\.pathFallback), ["/tmp/legacy-one", "/tmp/legacy-two"])
        let firstIDs = loaded.musicRoots.map(\.id)
        XCTAssertEqual(try store.loadSettings().musicRoots.map(\.id), firstIDs)
        let persisted = try XCTUnwrap(defaults.data(forKey: "nikoMusicHub.settings"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        XCTAssertNotNil(object["musicRoots"])
        XCTAssertNil(object["archiveRoots"])
    }

    func testRoundTripPersistsBookmarksAndSelectedIDs() throws {
        let defaults = try makeDefaults()
        let active = StoredMusicRoot(role: .active, url: URL(fileURLWithPath: "/tmp/active"), securityScopedBookmark: Data([1, 2]))
        let archive = StoredMusicRoot(role: .archive, url: URL(fileURLWithPath: "/tmp/archive"), securityScopedBookmark: Data([3, 4]))
        let settings = AppSettings(
            musicRoots: [active, archive],
            vault: VaultSettings(isEnabled: true, activeRootID: active.id, archiveRootID: archive.id)
        )
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        try store.saveSettings(settings)

        let loaded = try store.loadSettings()
        XCTAssertEqual(loaded.musicRoots, [active, archive])
        XCTAssertEqual(loaded.vault.activeRootID, active.id)
        XCTAssertEqual(loaded.vault.archiveRootID, archive.id)
    }

    func testDisabledVaultPreservesLegacyEffectiveScanRootsExactly() {
        let legacy = [StoredArchiveRoot(path: "/tmp/one"), StoredArchiveRoot(path: "/tmp/two")]
        var settings = AppSettings(archiveRoots: legacy)
        settings.musicRoots.append(StoredMusicRoot(role: .active, url: URL(fileURLWithPath: "/tmp/active")))
        settings.musicRoots.append(StoredMusicRoot(role: .archive, url: URL(fileURLWithPath: "/tmp/archive")))
        settings.vault.isEnabled = false

        XCTAssertEqual(settings.effectiveScanRoots.map(\.pathFallback), legacy.map(\.path))
        XCTAssertEqual(settings.archiveRoots, legacy)
    }

    func testEnabledVaultDeduplicatesScanOnlyAndSelectedActiveRootByCanonicalPath() {
        let sharedURL = URL(fileURLWithPath: "/tmp/shared-projects")
        let scanOnly = StoredMusicRoot(role: .scanOnly, url: sharedURL)
        let active = StoredMusicRoot(role: .active, url: sharedURL)
        let archive = StoredMusicRoot(role: .archive, url: URL(fileURLWithPath: "/tmp/vault-archive"))
        let settings = AppSettings(
            musicRoots: [scanOnly, active, archive],
            vault: VaultSettings(
                isEnabled: true,
                activeRootID: active.id,
                archiveRootID: archive.id
            )
        )

        XCTAssertEqual(settings.effectiveScanRoots.map(\.id), [active.id, archive.id])
    }

    func testReplacingRootsChangesOnlySettingsAndDoesNotMoveContent() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let active = base.appendingPathComponent("active", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let marker = active.appendingPathComponent("Song.cpr")
        try Data("untouched".utf8).write(to: marker)
        defer { try? FileManager.default.removeItem(at: base) }

        let manager = VaultRootManager(
            bookmarks: StubBookmarkProvider(),
            validator: MusicRootValidator(applicationDataRoots: [])
        )
        var settings = try manager.replacingRoot(role: .active, with: active, in: .default)
        settings = try manager.replacingRoot(role: .archive, with: archive, in: settings)

        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertNotNil(settings.vault.activeRootID)
        XCTAssertNotNil(settings.vault.archiveRootID)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "VaultSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private struct StubBookmarkProvider: SecurityScopedBookmarkProviding {
    func makeBookmark(for url: URL) throws -> Data { Data(url.path.utf8) }
}
