import AppCore
import Foundation
import NikoMusicCore
import XCTest

final class LiveProjectVaultRuntimeTests: XCTestCase {
    func testDoneArchivesImmediatelyButPrivateBetaRetainsActiveCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let runtime = try fixture.runtime()

        let snapshot = try await runtime.archive(song: fixture.song, trigger: .workflowDone)

        XCTAssertEqual(snapshot.transfer?.state, .archiveVerified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(snapshot.transfer).destinationURL.path))
    }

    func testDoneInFriendsRemovesOnlyAfterVerificationAndRestoreReturnsProject() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .friends, backupConfirmed: true)
        let runtime = try fixture.runtime()

        let archived = try await runtime.archive(song: fixture.song, trigger: .workflowDone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue([VaultTransferState.archivedLocal, .archivedOnlineOnly].contains(try XCTUnwrap(archived.transfer).state))

        let restore = try await runtime.restoreAndOpen(snapshot: archived)
        XCTAssertNotNil(restore.completedAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archived.transfer!.destinationURL.path))
    }
}

private extension LiveProjectVaultRuntimeTests {
    struct ClearProbe: VaultAutomationActivityProbing {
        func cubaseStatus() async -> VaultActivityStatus { .clear }
        func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { .clear }
        func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus { .clear }
    }

    final class Fixture {
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
            root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-runtime-\(UUID().uuidString)")
            active = root.appendingPathComponent("Active")
            archive = root.appendingPathComponent("Archive")
            project = active.appendingPathComponent("Synthetic Song")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            try Data("synthetic-cpr".utf8).write(to: project.appendingPathComponent("Synthetic Song.cpr"))
            database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("vault.sqlite"))
            suite = "LiveProjectVaultRuntimeTests.\(UUID().uuidString)"
            settingsStore = UserDefaultsSettingsStore(userDefaults: UserDefaults(suiteName: suite)!)
        }

        var song: Song {
            let cpr = project.appendingPathComponent("Synthetic Song.cpr")
            let version = ProjectVersion(filePath: cpr, fileName: cpr.lastPathComponent, modifiedAt: Date(timeIntervalSince1970: 1))
            return Song(
                folderPath: project,
                originalFolderName: project.lastPathComponent,
                displayTitle: "Synthetic Song",
                projectVersions: [version],
                latestCPR: version,
                workflowStatus: .done
            )
        }

        func saveSettings(stage: VaultSettings.RolloutStage, backupConfirmed: Bool) throws {
            var settings = AppSettings.default
            settings.musicRoots = [
                StoredMusicRoot(id: activeID, role: .active, url: active),
                StoredMusicRoot(id: archiveID, role: .archive, url: archive)
            ]
            settings.vault = VaultSettings(
                isEnabled: true,
                activeRootID: activeID,
                archiveRootID: archiveID,
                automaticArchiving: true,
                rolloutStage: stage,
                independentBackupConfirmed: backupConfirmed
            )
            try settingsStore.saveSettings(settings)
        }

        func runtime() throws -> LiveProjectVaultRuntime {
            try LiveProjectVaultRuntime(
                settingsStore: settingsStore,
                transferStore: SQLiteVaultTransferStore(database: database),
                catalogStore: SQLiteProjectCatalogStore(database: database),
                projectOpener: SafeVaultProjectOpener(),
                activityProbe: ClearProbe()
            )
        }

        func cleanup() {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
