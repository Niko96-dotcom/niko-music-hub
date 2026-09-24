import AppCore
import Foundation
import NikoMusicCore
import XCTest

/// D1: corrupt settings fail closed on load, and an explicit Repair Settings
/// click is the only way out: back up the raw blob, keep every field that still
/// decodes (vault sub-fields included), save, and say in plain words what reset.
final class SettingsRepairTests: XCTestCase {
    private let key = "nikoMusicHub.settings"
    private var cleanup: [URL] = []

    override func tearDown() {
        for url in cleanup { try? FileManager.default.removeItem(at: url) }
        cleanup = []
        super.tearDown()
    }

    func testCorruptVaultSubFieldRepairKeepsEverythingElseWritesBackupAndUnblocksSaves() throws {
        let (defaults, suite) = makeDefaults()
        let root = URL(fileURLWithPath: "/Volumes/Music/Archive", isDirectory: true)
        let rootEntry = StoredMusicRoot(role: .scanOnly, url: root)
        let vault = VaultSettings(
            isEnabled: true,
            automaticArchiving: false,
            inactivityDays: 45,
            minimumFreeSpaceGiB: 200,
            launchAtLogin: false,
            rolloutStage: .privateBeta,
            spaceIntent: .keepCopy,
            independentBackupConfirmed: true,
            keepLocalProjectIDs: ["song-a", "song-b"]
        )
        var settings = AppSettings(
            outputFolder: StoredFolderLocation(url: URL(fileURLWithPath: "/Users/test/Out", isDirectory: true)),
            maxRecordingDurationMinutes: 60,
            musicRoots: [rootEntry],
            vault: vault,
            appearance: .dark,
            archiveOnboardingCompleted: true,
            scanExclusionTerms: "backup, tmp",
            showMenuBarExtra: false
        )
        settings.setupAssistantShown = true
        let blob = try corrupting(settings) { object in
            var vault = object["vault"] as! [String: Any]
            vault["spaceIntent"] = "bogus"
            object["vault"] = vault
        }
        defaults.set(blob, forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        XCTAssertThrowsError(try store.loadSettings(), "normal load stays fail-closed")
        XCTAssertTrue(store.storedSettingsNeedRepair())

        let backupDirectory = makeTempDirectory(suite).appendingPathComponent("Settings Backups", isDirectory: true)
        let outcome = try XCTUnwrap(try store.repairStoredSettings(backupDirectory: backupDirectory))

        // Backup holds the exact raw bytes that were stored before the repair.
        XCTAssertEqual(try Data(contentsOf: outcome.backupURL), blob)
        XCTAssertTrue(outcome.backupURL.path.hasPrefix(backupDirectory.path))

        let repaired = try store.loadSettings()
        XCTAssertEqual(repaired.musicRoots.map(\.fallbackURL.path), [root.path])
        XCTAssertEqual(repaired.outputFolder.url.path, "/Users/test/Out")
        XCTAssertEqual(repaired.maxRecordingDurationMinutes, 60)
        XCTAssertEqual(repaired.appearance, .dark)
        XCTAssertTrue(repaired.archiveOnboardingCompleted)
        XCTAssertEqual(repaired.scanExclusionTerms, "backup, tmp")
        XCTAssertFalse(repaired.showMenuBarExtra)
        XCTAssertTrue(repaired.setupAssistantShown)
        // Valid vault sub-fields survive; only the broken one is defaulted.
        XCTAssertTrue(repaired.vault.isEnabled)
        XCTAssertEqual(repaired.vault.inactivityDays, 45)
        XCTAssertEqual(repaired.vault.minimumFreeSpaceGiB, 200)
        XCTAssertFalse(repaired.vault.launchAtLogin)
        XCTAssertEqual(repaired.vault.rolloutStage, .privateBeta)
        XCTAssertTrue(repaired.vault.independentBackupConfirmed)
        XCTAssertEqual(repaired.vault.keepLocalProjectIDs, ["song-a", "song-b"])
        XCTAssertEqual(repaired.vault.spaceIntent, .keepCopy)

        XCTAssertEqual(outcome.resetFields, ["Project Vault free-space rule"])
        XCTAssertEqual(
            outcome.message,
            "Repaired settings. Reset to default: Project Vault free-space rule. A backup was saved."
        )

        // The next ordinary save works again.
        try store.updateSettings { $0.appearance = .light }
        XCTAssertEqual(try store.loadSettings().appearance, .light)
        XCTAssertFalse(store.storedSettingsNeedRepair())
    }

    func testCorruptSpaceIntentNeverRepairsIntoFreeSpacePermission() throws {
        let (defaults, _) = makeDefaults()
        let blob = Data(#"{"vault":{"isEnabled":true,"rolloutStage":"friends","spaceIntent":"bogus","automaticArchiving":true}}"#.utf8)
        defaults.set(blob, forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)

        let outcome = try XCTUnwrap(try store.repairStoredSettings(backupDirectory: makeTempDirectory("intent")))
        let repaired = try store.loadSettings()

        XCTAssertEqual(repaired.vault.spaceIntent, .keepCopy)
        XCTAssertNotEqual(repaired.vault.rolloutStage, .friends, "legacy rollout must not keep removal permission")
        XCTAssertFalse(repaired.vault.automaticArchiving, "background archiving pauses after any vault repair")
        XCTAssertTrue(outcome.resetFields.contains("automatic archiving"))
    }

    func testUnreadableArchiveFolderEntryIsDroppedWhileOthersSurvive() throws {
        let (defaults, _) = makeDefaults()
        let good = StoredMusicRoot(role: .scanOnly, url: URL(fileURLWithPath: "/Volumes/Music/Good", isDirectory: true))
        let blob = try corrupting(AppSettings(musicRoots: [good])) { object in
            var roots = object["musicRoots"] as! [Any]
            roots.append(["role": 42])
            object["musicRoots"] = roots
        }
        defaults.set(blob, forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        XCTAssertThrowsError(try store.loadSettings())

        let outcome = try XCTUnwrap(try store.repairStoredSettings(backupDirectory: makeTempDirectory("roots")))

        XCTAssertEqual(try store.loadSettings().musicRoots.map(\.fallbackURL.path), ["/Volumes/Music/Good"])
        XCTAssertEqual(
            outcome.message,
            "Repaired settings. Removed 1 unreadable archive folder. A backup was saved."
        )
    }

    func testBackupWriteFailureChangesNothing() throws {
        let (defaults, suite) = makeDefaults()
        let blob = Data(#"{"appearance":"light","vault":{"spaceIntent":"bogus","keepLocalProjectIDs":["song-a"]}}"#.utf8)
        defaults.set(blob, forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        // A regular file where the backup folder's parent should be: the folder
        // cannot be created, so the backup cannot be written.
        let blocker = makeTempDirectory(suite).appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let backupDirectory = blocker.appendingPathComponent("Settings Backups", isDirectory: true)

        XCTAssertThrowsError(try store.repairStoredSettings(backupDirectory: backupDirectory)) { error in
            XCTAssertEqual(error as? SettingsRepairError, .backupFailed)
        }
        XCTAssertEqual(defaults.data(forKey: key), blob, "a failed backup must leave the stored settings untouched")
        XCTAssertTrue(store.storedSettingsNeedRepair())
    }

    func testValidSettingsAreNotOfferedRepair() throws {
        let (defaults, _) = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        try store.updateSettings { $0.appearance = .dark }
        let before = defaults.data(forKey: key)
        let backupDirectory = makeTempDirectory("valid").appendingPathComponent("Settings Backups", isDirectory: true)

        XCTAssertFalse(store.storedSettingsNeedRepair())
        XCTAssertNil(try store.repairStoredSettings(backupDirectory: backupDirectory))
        XCTAssertEqual(defaults.data(forKey: key), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupDirectory.path), "no backup for healthy settings")
    }

    @MainActor
    func testRepairModelOffersRepairOnlyForCorruptSettingsAndReportsOutcome() throws {
        let (defaults, suite) = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        let healthy = SettingsRepairModel(store: store, backupDirectory: makeTempDirectory(suite))
        XCTAssertFalse(healthy.needsRepair)

        defaults.set(Data(#"{"vault":{"spaceIntent":"bogus"}}"#.utf8), forKey: key)
        let model = SettingsRepairModel(store: store, backupDirectory: makeTempDirectory(suite + "-b"))
        XCTAssertTrue(model.needsRepair)
        XCTAssertEqual(SettingsRepairModel.pausedMessage, "Some settings couldn't be read, so changes are paused to protect them.")

        XCTAssertTrue(model.repair())
        XCTAssertFalse(model.needsRepair)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(
            model.resultMessage,
            "Repaired settings. Reset to default: Project Vault free-space rule. A backup was saved."
        )
    }

    @MainActor
    func testRepairModelShowsPlainErrorWhenBackupFails() throws {
        let (defaults, suite) = makeDefaults()
        let blob = Data(#"{"vault":{"spaceIntent":"bogus"}}"#.utf8)
        defaults.set(blob, forKey: key)
        let blocker = makeTempDirectory(suite).appendingPathComponent("file")
        try Data("x".utf8).write(to: blocker)
        let model = SettingsRepairModel(
            store: UserDefaultsSettingsStore(userDefaults: defaults),
            backupDirectory: blocker.appendingPathComponent("Settings Backups", isDirectory: true)
        )

        XCTAssertFalse(model.repair())
        XCTAssertTrue(model.needsRepair)
        XCTAssertEqual(model.errorMessage, "The backup couldn't be saved, so nothing was changed.")
        XCTAssertEqual(defaults.data(forKey: key), blob)
    }

    @MainActor
    func testRepairGenerationIncrementsOnRealRepair() throws {
        let (defaults, suite) = makeDefaults()
        defaults.set(Data(#"{"vault":{"spaceIntent":"bogus"}}"#.utf8), forKey: key)
        let model = SettingsRepairModel(
            store: UserDefaultsSettingsStore(userDefaults: defaults),
            backupDirectory: makeTempDirectory(suite)
        )

        XCTAssertEqual(model.repairGeneration, 0)
        XCTAssertTrue(model.repair())
        XCTAssertEqual(model.repairGeneration, 1)
    }

    @MainActor
    func testRepairGenerationStaysUnchangedOnNoOpRepair() throws {
        let (defaults, suite) = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        try store.updateSettings { $0.appearance = .dark }
        let model = SettingsRepairModel(store: store, backupDirectory: makeTempDirectory(suite))

        XCTAssertEqual(model.repairGeneration, 0)
        XCTAssertTrue(model.repair())
        XCTAssertEqual(model.repairGeneration, 0, "a no-op repair of a readable blob must not bump the generation")
    }

    @MainActor
    func testRepairGenerationStaysUnchangedWhenBackupDirectoryIsMissing() throws {
        let (defaults, _) = makeDefaults()
        defaults.set(Data(#"{"vault":{"spaceIntent":"bogus"}}"#.utf8), forKey: key)
        let model = SettingsRepairModel(
            store: UserDefaultsSettingsStore(userDefaults: defaults),
            backupDirectory: nil
        )

        XCTAssertEqual(model.repairGeneration, 0)
        XCTAssertFalse(model.repair())
        XCTAssertEqual(model.repairGeneration, 0, "a failed repair must not bump the generation")
    }

    // MARK: - Salvage never increases destructive permission (R1/R2)

    /// Every removal/archiving gate, most permissive first.
    private func permissions(_ vault: VaultSettings) -> [String: Bool] {
        [
            "automaticArchiving": ProjectVaultRolloutPolicy.permitsAutomaticArchiving(vault),
            "userInitiatedArchiving": ProjectVaultRolloutPolicy.permitsUserInitiatedArchiving(vault),
            "activeCopyRemoval": ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(vault),
            "userInitiatedRemoval": ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(vault),
        ]
    }

    /// A vault that currently permits everything (removal included).
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
            "lastSuccessfulVerificationAt": 700_000_000.0,
            "lastRestoreDrillAt": 700_000_000.0,
            "keepLocalProjectIDs": ["pinned-a", "pinned-b"],
        ]
    }

    /// Fields that on their own gate removal: when any of them is unreadable
    /// the repaired settings must permit no removal at all.
    private let removalGatingFields: Set<String> = [
        "isEnabled", "activeRootID", "archiveRootID", "rolloutStage", "spaceIntent",
        "automationEmergencyStop", "independentBackupConfirmed", "keepLocalProjectIDs",
    ]

    func testEveryUnreadableVaultFieldRepairsToTheLeastDestructiveValue() throws {
        let junkValues: [Any] = [["junk": true], "junk", NSNull(), 7]
        for field in permissiveVaultObject().keys.sorted() {
            for junk in junkValues {
                var vault = permissiveVaultObject()
                vault[field] = junk
                let blob = try JSONSerialization.data(withJSONObject: ["vault": vault])
                let before = try? JSONDecoder().decode(AppSettings.self, from: blob)
                guard before == nil else { continue } // this junk happens to decode for this field
                let (defaults, _) = makeDefaults()
                defaults.set(blob, forKey: key)
                let store = UserDefaultsSettingsStore(userDefaults: defaults)

                let outcome = try XCTUnwrap(
                    try store.repairStoredSettings(backupDirectory: makeTempDirectory("table-\(field)")),
                    "\(field)=\(junk)"
                )
                let repaired = try store.loadSettings().vault
                let baseline = try JSONDecoder().decode(
                    VaultSettings.self,
                    from: JSONSerialization.data(withJSONObject: permissiveVaultObject())
                )

                for (gate, allowed) in permissions(repaired) where allowed {
                    XCTAssertTrue(permissions(baseline)[gate] == true, "\(field)=\(junk): repair granted \(gate)")
                }
                XCTAssertFalse(repaired.automaticArchiving, "\(field)=\(junk): background archiving must pause")
                if removalGatingFields.contains(field) {
                    XCTAssertFalse(permissions(repaired)["userInitiatedRemoval"]!, "\(field)=\(junk): removal must be denied")
                    XCTAssertFalse(permissions(repaired)["activeCopyRemoval"]!, "\(field)=\(junk): removal must be denied")
                }
                XCTAssertFalse(outcome.message.isEmpty)
            }
        }
    }

    func testRepairNeverGrantsPermissionThatAStoppedVaultLacked() throws {
        // Emergency stop on + keep a copy + no backup confirmation: nothing is
        // permitted. Corrupting any single other field must not change that.
        var restrictive = permissiveVaultObject()
        restrictive["automationEmergencyStop"] = true
        restrictive["spaceIntent"] = "keepCopy"
        restrictive["independentBackupConfirmed"] = false
        for field in restrictive.keys.sorted() {
            var vault = restrictive
            vault[field] = ["junk": true]
            let (defaults, _) = makeDefaults()
            defaults.set(try JSONSerialization.data(withJSONObject: ["vault": vault]), forKey: key)
            let store = UserDefaultsSettingsStore(userDefaults: defaults)
            _ = try store.repairStoredSettings(backupDirectory: makeTempDirectory("restrictive-\(field)"))
            let repaired = try store.loadSettings().vault
            XCTAssertFalse(permissions(repaired)["userInitiatedRemoval"]!, field)
            XCTAssertFalse(permissions(repaired)["activeCopyRemoval"]!, field)
            XCTAssertFalse(permissions(repaired)["automaticArchiving"]!, field)
        }
    }

    func testUnreadableEmergencyStopRepairsToOn() throws {
        for junk in ["1", #""true""#, "null"] {
            let (defaults, _) = makeDefaults()
            var vault = permissiveVaultObject()
            vault.removeValue(forKey: "automationEmergencyStop")
            var json = String(data: try JSONSerialization.data(withJSONObject: ["vault": vault]), encoding: .utf8)!
            json = json.replacingOccurrences(of: "\"isEnabled\"", with: "\"automationEmergencyStop\":\(junk),\"isEnabled\"")
            defaults.set(Data(json.utf8), forKey: key)
            let store = UserDefaultsSettingsStore(userDefaults: defaults)

            _ = try XCTUnwrap(try store.repairStoredSettings(backupDirectory: makeTempDirectory("stop")), junk)
            let repaired = try store.loadSettings().vault

            XCTAssertTrue(repaired.automationEmergencyStop, "unreadable stop \(junk) must repair to ON")
            XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(repaired), junk)
            // Everything else readable survives.
            XCTAssertTrue(repaired.independentBackupConfirmed)
            XCTAssertEqual(repaired.keepLocalProjectIDs, ["pinned-a", "pinned-b"])
        }
    }

    func testUnreadableKeepLocalListPausesRemovalAndSaysSo() throws {
        for junk: Any in ["pinned-a", ["pinned-a", 5], ["id": "pinned-a"]] {
            let (defaults, _) = makeDefaults()
            var vault = permissiveVaultObject()
            vault["keepLocalProjectIDs"] = junk
            let blob = try JSONSerialization.data(withJSONObject: ["vault": vault])
            defaults.set(blob, forKey: key)
            let store = UserDefaultsSettingsStore(userDefaults: defaults)

            let outcome = try XCTUnwrap(try store.repairStoredSettings(backupDirectory: makeTempDirectory("pins")))
            let repaired = try store.loadSettings().vault

            XCTAssertTrue(repaired.automationEmergencyStop, "\(junk)")
            XCTAssertEqual(repaired.spaceIntent, .keepCopy, "\(junk)")
            XCTAssertFalse(ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(repaired), "\(junk)")
            XCTAssertTrue(
                outcome.message.contains("Keep Local list couldn't be read — Project Vault removal is paused until you review it."),
                outcome.message
            )
            // The raw pin list stays recoverable from the backup.
            XCTAssertEqual(try Data(contentsOf: outcome.backupURL), blob)
        }
        // Readable pins inside a partly broken list are kept, never emptied.
        let (defaults, _) = makeDefaults()
        var vault = permissiveVaultObject()
        vault["keepLocalProjectIDs"] = ["pinned-a", 5]
        defaults.set(try JSONSerialization.data(withJSONObject: ["vault": vault]), forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        _ = try store.repairStoredSettings(backupDirectory: makeTempDirectory("partial-pins"))
        XCTAssertEqual(try store.loadSettings().vault.keepLocalProjectIDs, ["pinned-a"])
    }

    func testUnreadableVaultObjectPausesRemoval() throws {
        let (defaults, _) = makeDefaults()
        defaults.set(Data(#"{"vault":"broken"}"#.utf8), forKey: key)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        let outcome = try XCTUnwrap(try store.repairStoredSettings(backupDirectory: makeTempDirectory("vault")))
        let repaired = try store.loadSettings().vault
        XCTAssertTrue(repaired.automationEmergencyStop)
        XCTAssertTrue(outcome.message.contains("Project Vault removal is paused until you review it."), outcome.message)
    }

    // MARK: - First launch (R3)

    func testFirstLaunchSetupNeverAutoPresentsForUnreadableSettings() throws {
        let (defaults, _) = makeDefaults()
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        XCTAssertTrue(HubFirstLaunchSetupPolicy.shouldPresentSetup(store: store, runtimeAllowsAutoSetup: true),
                      "a brand-new install (no stored settings) still sees Set Up")
        XCTAssertFalse(HubFirstLaunchSetupPolicy.shouldPresentSetup(store: store, runtimeAllowsAutoSetup: false))

        defaults.set(Data(#"{"vault":{"spaceIntent":"bogus"}}"#.utf8), forKey: key)
        XCTAssertFalse(HubFirstLaunchSetupPolicy.shouldPresentSetup(store: store, runtimeAllowsAutoSetup: true),
                       "damaged settings belong to a returning user; never show the new-user sheet")

        defaults.set(Data(#"{"setupAssistantShown":true}"#.utf8), forKey: key)
        XCTAssertFalse(HubFirstLaunchSetupPolicy.shouldPresentSetup(store: store, runtimeAllowsAutoSetup: true))
    }

    func testAppCompositionUsesFirstLaunchPolicy() throws {
        let source = try String(contentsOfFile: "Sources/NikoMusicHub/AppComposition.swift", encoding: .utf8)
        XCTAssertTrue(source.contains("HubFirstLaunchSetupPolicy.shouldPresentSetup("))
        XCTAssertFalse(source.contains("let launchSettings = (try? settingsStore.loadSettings()) ?? .default"))
    }

    // MARK: - Helpers

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "SettingsRepairTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func makeTempDirectory(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-settings-repair-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        cleanup.append(url)
        return url
    }

    private func corrupting(_ settings: AppSettings, _ mutate: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )
        mutate(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }
}
