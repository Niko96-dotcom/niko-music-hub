import AppCore
import Foundation
import XCTest
@testable import FeatureArchiveBrowser
import NikoMusicCore

/// R3/R4: the archive pane after a settings repair, and while settings are
/// unreadable. The settings-repair notice owns that explanation; the archive
/// never shows raw decoding errors or the new-user sheet for it.
@MainActor
final class ArchiveSettingsRepairTests: XCTestCase {
    private let key = "nikoMusicHub.settings"

    override func setUp() {
        super.setUp()
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
    }

    func testVaultReadFailureUsesPlainCopyWithoutRawError() async {
        let runtime = ToggleFailingVaultRuntime(failing: true)
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: makeStore(blob: nil)),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime
        )

        await viewModel.refreshProjectVaultSnapshots()

        XCTAssertEqual(viewModel.persistenceWarningMessage, "Project Vault status couldn't be read. Nothing was changed.")
        XCTAssertFalse(viewModel.statusMessage?.contains("injected") == true)
    }

    func testVaultReadFailureStaysQuietWhileSettingsAreUnreadable() async {
        let runtime = ToggleFailingVaultRuntime(failing: true)
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: makeStore(blob: Data(#"{"vault":{"spaceIntent":"bogus"}}"#.utf8))),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime
        )

        await viewModel.refreshProjectVaultSnapshots()
        await viewModel.recoverProjectVaultAndRefresh()

        XCTAssertFalse(viewModel.persistenceWarningMessage?.contains("Project Vault") == true,
                       "the settings-repair notice already explains this, got: \(viewModel.persistenceWarningMessage ?? "nil")")
    }

    func testRepairedSettingsRefreshVaultStatusAndClearTheWarning() async throws {
        let runtime = ToggleFailingVaultRuntime(failing: true)
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: makeStore(blob: nil)),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime
        )
        await viewModel.refreshProjectVaultSnapshots()
        XCTAssertNotNil(viewModel.persistenceWarningMessage)

        await runtime.setFailing(false)
        viewModel.applyRepairedSettings()
        for _ in 0..<200 where viewModel.persistenceWarningMessage != nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNil(viewModel.persistenceWarningMessage, "a successful repair must refresh Vault status without a relaunch")
        let refreshes = await runtime.snapshotCallCount()
        XCTAssertGreaterThanOrEqual(refreshes, 2)
    }

    func testUnreadableSettingsNeverShowTheArchiveFirstRunSheet() {
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: makeStore(blob: Data(#"{"vault":{"spaceIntent":"bogus"}}"#.utf8))),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )
        viewModel.roots = []
        viewModel.refreshFirstRunState()

        XCTAssertFalse(viewModel.needsFirstRunOnboarding, "damaged settings belong to a returning user")
    }

    func testUnreadableSettingsLoadAddsNoArchiveWarning() {
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: makeStore(blob: Data(#"{"vault":{"spaceIntent":"bogus"}}"#.utf8))),
            archiveRootWatcher: NoopArchiveRootWatcher()
        )

        XCTAssertNil(viewModel.persistenceWarningMessage,
                     "the settings-repair notice already explains this")
        XCTAssertFalse(viewModel.statusMessage?.contains("correct format") == true,
                       "raw decoding error leaked: \(viewModel.statusMessage ?? "nil")")
    }

    func testUnreadableSettingsRefuseRootAndOnboardingSavesWithThePlainSentence() async throws {
        let blob = Data(#"{"vault":{"spaceIntent":"bogus"}}"#.utf8)
        let defaults = makeDefaults(blob: blob)
        let store = UserDefaultsSettingsStore(userDefaults: defaults)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-repair-root-\(UUID().uuidString)", isDirectory: true)
        let backups = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-repair-backups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: backups)
        }
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in ScanResult(songs: [], globalWarnings: [], skippedEntries: []) }
        )
        let plain = try XCTUnwrap(ArchiveWriteGuardError.settingsUnreadable.errorDescription)

        viewModel.addRoot(root)
        XCTAssertEqual(viewModel.persistenceWarningMessage, plain)
        viewModel.persistenceWarningMessage = nil
        viewModel.completeArchiveOnboarding()
        XCTAssertEqual(viewModel.persistenceWarningMessage, plain)
        XCTAssertEqual(defaults.data(forKey: key), blob, "nothing was written")

        _ = try store.repairStoredSettings(backupDirectory: backups, now: Date())
        viewModel.applyRepairedSettings()

        XCTAssertNil(viewModel.persistenceWarningMessage, "a repair clears the refusal")
    }

    // MARK: - Helpers

    private func makeDefaults(blob: Data?) -> UserDefaults {
        let suite = "ArchiveSettingsRepairTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if let blob { defaults.set(blob, forKey: key) }
        return defaults
    }

    private func makeStore(blob: Data?) -> UserDefaultsSettingsStore {
        UserDefaultsSettingsStore(userDefaults: makeDefaults(blob: blob))
    }
}

private actor ToggleFailingVaultRuntime: ProjectVaultOperating {
    private var failing: Bool
    private var snapshotCalls = 0

    init(failing: Bool) { self.failing = failing }

    func setFailing(_ value: Bool) { failing = value }
    func snapshotCallCount() -> Int { snapshotCalls }

    func snapshots() async throws -> [ProjectVaultRuntimeSnapshot] {
        snapshotCalls += 1
        if failing { throw ProjectVaultRuntimeError.archiveFailed("injected journal read failure") }
        return []
    }

    func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot {
        throw ProjectVaultRuntimeError.unavailable
    }

    func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
        throw ProjectVaultRuntimeError.unavailable
    }

    func recoverAtLaunch() async {}
}
