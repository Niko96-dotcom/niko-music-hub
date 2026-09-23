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
