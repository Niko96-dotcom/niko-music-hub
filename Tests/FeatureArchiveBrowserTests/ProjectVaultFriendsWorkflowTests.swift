import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

@MainActor
final class ProjectVaultFriendsWorkflowTests: XCTestCase {
    func testFriendsArchiveRemainsVisibleRestoresVerifiesAndKeepsLocalAcrossRelaunch() async throws {
        let fixture = try FriendsWorkflowFixture()
        defer { fixture.cleanup() }
        let runtime = try fixture.runtime()
        let viewModel = fixture.viewModel(runtime: runtime)

        await viewModel.scan()
        let activeSong = try XCTUnwrap(viewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })
        viewModel.updateWorkflowStatus(for: activeSong, status: .done)

        try await waitUntil {
            !FileManager.default.fileExists(atPath: fixture.project.path)
                && viewModel.projectVaultBusySongIDs.isEmpty
                && viewModel.songs.contains {
                    $0.originalFolderName == "Friends Workflow Song"
                        && viewModel.projectVaultPresentation(for: $0) != nil
                }
        }

        let workflowSongs = viewModel.songs.filter { $0.originalFolderName == "Friends Workflow Song" }
        XCTAssertEqual(workflowSongs.count, 1, "Unexpected project paths: \(workflowSongs.map(\.folderPath.path))")
        let archivedSong = try XCTUnwrap(workflowSongs.first)
        XCTAssertNotEqual(archivedSong.folderPath.standardizedFileURL, fixture.project.standardizedFileURL)
        let archivedPresentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: archivedSong))
        XCTAssertEqual(archivedPresentation.state, .archived)
        XCTAssertEqual(archivedPresentation.primaryAction, .restoreAndOpen)

        viewModel.setProjectKeepLocal(true, for: archivedSong)
        let pinnedArchivedPresentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: archivedSong))
        XCTAssertTrue(pinnedArchivedPresentation.isKeepLocal)
        XCTAssertEqual(pinnedArchivedPresentation.state, .archived)
        XCTAssertEqual(pinnedArchivedPresentation.primaryAction, .restoreAndOpen)

        viewModel.performProjectVaultPrimaryAction(for: archivedSong)
        try await waitUntil {
            FileManager.default.fileExists(atPath: fixture.project.path)
                && viewModel.projectVaultBusySongIDs.isEmpty
                && viewModel.statusMessage == "Restored, verified, and opened in Cubase."
        }

        let restoredSong = try XCTUnwrap(viewModel.songs.first { $0.folderPath.standardizedFileURL == fixture.project.standardizedFileURL })
        let restoredPresentation = try XCTUnwrap(viewModel.projectVaultPresentation(for: restoredSong))
        XCTAssertTrue(restoredPresentation.isKeepLocal)
        XCTAssertEqual(restoredPresentation.state, .keepLocal)
        XCTAssertEqual(restoredPresentation.primaryAction, .openInCubase)

        let transfer = try XCTUnwrap(try fixture.transferStore().verifiedArchiveGeneration(projectID: fixture.projectID()))
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
        try VaultManifestBuilder().verify(try XCTUnwrap(transfer.manifest), at: transfer.destinationURL)

        do {
            _ = try await runtime.archive(song: restoredSong, trigger: .workflowDone)
            XCTFail("Keep Local must block later automatic archiving")
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .keepLocal)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))

        let relaunchedRuntime = try fixture.runtime()
        await relaunchedRuntime.recoverAtLaunch()
        let relaunchedViewModel = fixture.viewModel(runtime: relaunchedRuntime)
        await relaunchedViewModel.scan()
        await relaunchedViewModel.refreshProjectVaultSnapshots()

        XCTAssertEqual(
            relaunchedViewModel.songs.filter { $0.originalFolderName == "Friends Workflow Song" }.count,
            1
        )
        let relaunchedSong = try XCTUnwrap(relaunchedViewModel.songs.first { $0.originalFolderName == "Friends Workflow Song" })
        XCTAssertEqual(relaunchedViewModel.projectVaultPresentation(for: relaunchedSong)?.state, .keepLocal)
        try VaultManifestBuilder().verify(fixture.sourceManifest, at: fixture.project)
        try VaultManifestBuilder().verify(try XCTUnwrap(transfer.manifest), at: transfer.destinationURL)
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for Friends workflow state")
    }
}

private struct FriendsClearActivityProbe: VaultAutomationActivityProbing {
    func cubaseStatus() async -> VaultActivityStatus { .clear }
    func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { .clear }
    func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus { .clear }
}

private final class FriendsWorkflowFixture {
    let root: URL
    let active: URL
    let archive: URL
    let project: URL
    let sourceManifest: VaultManifest
    let database: SQLiteArchiveDatabase
    let settingsStore: UserDefaultsSettingsStore
    let activeID = UUID()
    let archiveID = UUID()
    let suite: String

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("friends-workflow-\(UUID().uuidString)", isDirectory: true)
        active = root.appendingPathComponent("Active", isDirectory: true)
        archive = root.appendingPathComponent("Archive", isDirectory: true)
        project = active.appendingPathComponent("Friends Workflow Song", isDirectory: true)
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("Audio", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("friends-workflow-cpr".utf8)
            .write(to: project.appendingPathComponent("Friends Workflow Song.cpr"))
        try Data(repeating: 0x5a, count: 16_384)
            .write(to: project.appendingPathComponent("Audio/take.wav"))
        sourceManifest = try VaultManifestBuilder().build(at: project)
        database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("vault.sqlite"))
        suite = "ProjectVaultFriendsWorkflowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settingsStore = UserDefaultsSettingsStore(userDefaults: defaults)
        var settings = AppSettings.default
        settings.musicRoots = [
            StoredMusicRoot(id: activeID, role: .active, url: active),
            StoredMusicRoot(id: archiveID, role: .archive, url: archive),
        ]
        settings.vault = VaultSettings(
            isEnabled: true,
            activeRootID: activeID,
            archiveRootID: archiveID,
            automaticArchiving: true,
            rolloutStage: .friends,
            independentBackupConfirmed: true
        )
        try settingsStore.saveSettings(settings)
    }

    func runtime() throws -> LiveProjectVaultRuntime {
        try LiveProjectVaultRuntime(
            settingsStore: settingsStore,
            transferStore: transferStore(),
            catalogStore: catalogStore(),
            projectOpener: SafeVaultProjectOpener(),
            activityProbe: FriendsClearActivityProbe()
        )
    }

    @MainActor
    func viewModel(runtime: any ProjectVaultOperating) -> ArchiveBrowserViewModel {
        ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: settingsStore),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            projectVaultRuntime: runtime,
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.settingsSuiteKey: suite,
                MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
            ])
        )
    }

    func transferStore() throws -> SQLiteVaultTransferStore {
        try SQLiteVaultTransferStore(database: database)
    }

    func catalogStore() throws -> SQLiteProjectCatalogStore {
        try SQLiteProjectCatalogStore(database: database)
    }

    func projectID() throws -> ProjectID {
        try XCTUnwrap(try catalogStore().loadEntries().first?.record.id)
    }

    func cleanup() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
