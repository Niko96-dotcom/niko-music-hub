import AppCore
import Foundation
import NikoMusicCore
import XCTest

final class VaultSettingsTests: XCTestCase {
    /// ENG-10 pin: the converter, downloader, stems, recorder and Settings picker admit
    /// output through `ToolOutputGuard`. Turning Vault off hides its roots from browsing
    /// only; every configured root, the retained archive included, stays write-protected.
    func testToolOutputGuardRootsKeepVaultRootsWhateverTheVaultSwitch() throws {
        let archive = StoredMusicRoot(role: .archive, url: URL(fileURLWithPath: "/tmp/nmh-t23/VaultArchive"))
        let active = StoredMusicRoot(role: .active, url: URL(fileURLWithPath: "/tmp/nmh-t23/Active"))
        let scanOnly = StoredMusicRoot(role: .scanOnly, url: URL(fileURLWithPath: "/tmp/nmh-t23/Scan"))
        var settings = AppSettings()
        settings.musicRoots = [archive, active, scanOnly]
        settings.vault.archiveRootID = archive.id
        settings.vault.activeRootID = active.id
        let generation = archive.fallbackURL.appendingPathComponent("Song/generation-1", isDirectory: true)
        for vaultOn in [true, false] {
            settings.vault.isEnabled = vaultOn
            let outputGuard = ToolOutputGuard(settings: settings)
            for root in [archive, active, scanOnly] {
                XCTAssertThrowsError(
                    try outputGuard.validate(root.fallbackURL),
                    "\(root.role) root, vault on: \(vaultOn)"
                )
            }
            XCTAssertThrowsError(try outputGuard.validate(generation), "vault on: \(vaultOn)")
        }
        XCTAssertNoThrow(
            try ToolOutputGuard(settings: settings).validate(
                URL(fileURLWithPath: "/tmp/nmh-t23/Output", isDirectory: true)
            )
        )

        // Browsing still hides the Vault roots while Vault is off.
        settings.vault.isEnabled = true
        XCTAssertTrue(settings.archiveRoots.map(\.url.path).contains(archive.fallbackURL.path))
        settings.vault.isEnabled = false
        XCTAssertEqual(settings.archiveRoots.map(\.url.path), [scanOnly.fallbackURL.path])
    }

    /// A root renamed in Finder keeps its bookmark but not its stored path; the bookmark's
    /// current location must stay write-protected for every role.
    func testToolOutputGuardProtectsTheBookmarkedLocationOfAMovedRoot() throws {
        struct MovedBookmarks: SecurityScopedBookmarkResolving {
            let locations: [Data: URL]
            func resolveBookmark(_ data: Data) throws -> URL {
                throw SecurityScopedBookmarkError.staleBookmark
            }
            func currentLocation(ofBookmark data: Data) -> URL? { locations[data] }
        }
        let roles: [MusicRootRole] = [.archive, .active, .scanOnly]
        var settings = AppSettings()
        var locations: [Data: URL] = [:]
        settings.musicRoots = roles.map { role in
            let bookmark = Data(role.rawValue.utf8)
            locations[bookmark] = URL(fileURLWithPath: "/tmp/nmh-l573/\(role.rawValue) 2026", isDirectory: true)
            return StoredMusicRoot(
                role: role,
                url: URL(fileURLWithPath: "/tmp/nmh-l573/\(role.rawValue)"),
                securityScopedBookmark: bookmark
            )
        }
        let outputGuard = ToolOutputGuard(settings: settings, bookmarks: MovedBookmarks(locations: locations))
        for role in roles {
            let moved = URL(fileURLWithPath: "/tmp/nmh-l573/\(role.rawValue) 2026/Out", isDirectory: true)
            XCTAssertThrowsError(try outputGuard.validate(moved), "\(role) root moved")
            XCTAssertThrowsError(
                try outputGuard.validate(URL(fileURLWithPath: "/tmp/nmh-l573/\(role.rawValue)/Out", isDirectory: true)),
                "\(role) root stored path"
            )
        }
        XCTAssertNoThrow(try outputGuard.validate(URL(fileURLWithPath: "/tmp/nmh-l573/Output", isDirectory: true)))
    }

    func testVaultDefaultsAreOptInAndMatchPolicy() {
        let vault = AppSettings.default.vault
        XCTAssertFalse(vault.isEnabled)
        XCTAssertNil(vault.activeRootID)
        XCTAssertNil(vault.archiveRootID)
        XCTAssertEqual(vault.transferFreeSpaceReserveGiB, 5)
        XCTAssertEqual(vault.keepPreviousGenerationDays, 30)
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
        XCTAssertThrowsError(
            try JSONDecoder().decode(AppSettings.self, from: wrapped),
            "a present corrupt intent inside AppSettings must throw instead of falling back to whole-vault defaults"
        ) { _ in
            XCTAssertFalse(
                (try? JSONDecoder().decode(AppSettings.self, from: wrapped)).map {
                    ProjectVaultRolloutPolicy.expressesFreeSpaceIntent($0.vault)
                } ?? false,
                "corrupt intent must never decode to free space"
            )
        }
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
        XCTAssertThrowsError(
            try JSONDecoder().decode(AppSettings.self, from: wrapped),
            "an explicit null intent inside AppSettings must throw instead of falling back to whole-vault defaults"
        ) { _ in
            XCTAssertFalse(
                (try? JSONDecoder().decode(AppSettings.self, from: wrapped)).map {
                    ProjectVaultRolloutPolicy.expressesFreeSpaceIntent($0.vault)
                } ?? false,
                "explicit null must never decode to free space"
            )
        }
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

    func testPresentNullNonoptionalVaultFieldsThrow() throws {
        let payloads = [
            #"{"isEnabled":null}"#,
            #"{"transferFreeSpaceReserveGiB":null}"#,
            #"{"keepPreviousGenerationDays":null}"#,
            #"{"rolloutStage":null}"#,
            #"{"automationEmergencyStop":null}"#,
            #"{"independentBackupConfirmed":null}"#,
            #"{"keepLocalProjectIDs":null}"#,
            #"{"isEnabled":"bogus"}"#,
            #"{"keepLocalProjectIDs":"bogus"}"#,
        ]
        for payload in payloads {
            XCTAssertThrowsError(
                try JSONDecoder().decode(VaultSettings.self, from: Data(payload.utf8)),
                "present malformed vault field must throw: \(payload)"
            )
            let wrapped = Data(#"{"vault":\#(payload)}"#.utf8)
            XCTAssertThrowsError(
                try JSONDecoder().decode(AppSettings.self, from: wrapped),
                "present malformed vault field inside AppSettings must throw: \(payload)"
            )
        }
    }

    func testMissingNonoptionalVaultKeysDecodeToLegacyDefaults() throws {
        let empty = try JSONDecoder().decode(VaultSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, VaultSettings())

        let partial = try JSONDecoder().decode(
            VaultSettings.self,
            from: Data(#"{"isEnabled":true}"#.utf8)
        )
        XCTAssertTrue(partial.isEnabled)
        XCTAssertEqual(partial.transferFreeSpaceReserveGiB, 5)
        XCTAssertEqual(partial.keepPreviousGenerationDays, 30)
        XCTAssertEqual(partial.rolloutStage, .disabled)
        XCTAssertEqual(partial.spaceIntent, .keepCopy)
        XCTAssertFalse(partial.automationEmergencyStop)
        XCTAssertFalse(partial.independentBackupConfirmed)
        XCTAssertEqual(partial.keepLocalPins.storedKeys, [])
    }

    func testOptionalVaultFieldsAcceptMissingAndNull() throws {
        let empty = try JSONDecoder().decode(VaultSettings.self, from: Data("{}".utf8))
        XCTAssertNil(empty.activeRootID)
        XCTAssertNil(empty.archiveRootID)
        XCTAssertNil(empty.lastSuccessfulVerificationAt)
        XCTAssertNil(empty.lastRestoreDrillAt)

        let nulled = try JSONDecoder().decode(
            VaultSettings.self,
            from: Data(#"{"activeRootID":null,"archiveRootID":null,"lastSuccessfulVerificationAt":null,"lastRestoreDrillAt":null}"#.utf8)
        )
        XCTAssertNil(nulled.activeRootID)
        XCTAssertNil(nulled.archiveRootID)
        XCTAssertNil(nulled.lastSuccessfulVerificationAt)
        XCTAssertNil(nulled.lastRestoreDrillAt)
    }

    func testSettingsWithTheRemovedArchivingSwitchLoadWithoutRepairAndKeepEveryOtherValue() throws {
        // 1.8.1 wrote the background-archiving switch, its two thresholds and
        // the Vault login flag. They load without a repair, every other value
        // stays, the old pressure threshold does not leak into the reserve,
        // and the next save drops them.
        let activeID = UUID()
        let archiveID = UUID()
        let verifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let vault = #"""
        {"isEnabled":true,"activeRootID":"\#(activeID.uuidString)","archiveRootID":"\#(archiveID.uuidString)",\#
        "automaticArchiving":true,"inactivityDays":45,"minimumFreeSpaceGiB":200,"launchAtLogin":false,\#
        "keepPreviousGenerationDays":14,"rolloutStage":"friends","spaceIntent":"freeSpace",\#
        "automationEmergencyStop":false,"independentBackupConfirmed":true,\#
        "lastSuccessfulVerificationAt":\#(verifiedAt.timeIntervalSinceReferenceDate),\#
        "keepLocalProjectIDs":["song-a"],"keepLocalReviewRequired":false}
        """#
        let defaults = try makeDefaults()
        defaults.set(Data(#"{"appearance":"dark","vault":\#(vault)}"#.utf8), forKey: "nikoMusicHub.settings")
        let store = UserDefaultsSettingsStore(userDefaults: defaults)

        let loaded = try store.loadSettings()
        XCTAssertEqual(loaded.appearance, .dark)
        XCTAssertEqual(
            loaded.vault,
            VaultSettings(
                isEnabled: true,
                activeRootID: activeID,
                archiveRootID: archiveID,
                transferFreeSpaceReserveGiB: 5,
                keepPreviousGenerationDays: 14,
                rolloutStage: .friends,
                spaceIntent: .freeSpace,
                independentBackupConfirmed: true,
                lastSuccessfulVerificationAt: verifiedAt,
                keepLocalProjectIDs: ["song-a"]
            )
        )

        try store.updateSettings { $0.appearance = .light }
        let saved = try XCTUnwrap(defaults.data(forKey: "nikoMusicHub.settings"))
        let savedVault = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: saved) as? [String: Any])?["vault"] as? [String: Any]
        )
        for key in ["automaticArchiving", "inactivityDays", "minimumFreeSpaceGiB", "launchAtLogin"] {
            XCTAssertNil(savedVault[key], key)
        }
        XCTAssertEqual(try store.loadSettings().vault, loaded.vault)
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
