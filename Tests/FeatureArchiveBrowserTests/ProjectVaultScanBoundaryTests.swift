import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

@MainActor
final class ProjectVaultScanBoundaryTests: XCTestCase {
    func testApplyingVaultSettingsRefreshesMountedArchiveRootsAndScansWithoutRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-settings-refresh-\(UUID())")
        let initialActive = root.appendingPathComponent("Initial Active")
        let initialArchive = root.appendingPathComponent("Initial Archive")
        let updatedActive = root.appendingPathComponent("Updated Active")
        let updatedArchive = root.appendingPathComponent("Updated Archive")
        let updatedSong = updatedActive.appendingPathComponent("Fresh Project")
        try FileManager.default.createDirectory(at: initialActive, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: initialArchive, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: updatedArchive, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: updatedSong, withIntermediateDirectories: true)
        try Data("updated-cpr".utf8).write(to: updatedSong.appendingPathComponent("Fresh Project.cpr"))
        defer { try? FileManager.default.removeItem(at: root) }

        let initialActiveRoot = StoredMusicRoot(role: .active, url: initialActive)
        let initialArchiveRoot = StoredMusicRoot(role: .archive, url: initialArchive)
        let updatedActiveRoot = StoredMusicRoot(role: .active, url: updatedActive)
        let updatedArchiveRoot = StoredMusicRoot(role: .archive, url: updatedArchive)
        let suite = "ProjectVaultScanBoundarySettingsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(userDefaults: defaults)

        var settings = AppSettings.default
        settings.musicRoots = [initialActiveRoot, initialArchiveRoot]
        settings.vault = VaultSettings(
            isEnabled: true,
            activeRootID: initialActiveRoot.id,
            archiveRootID: initialArchiveRoot.id,
            rolloutStage: .privateBeta
        )
        try store.saveSettings(settings)

        let model = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: store),
            archiveRootWatcher: NoopArchiveRootWatcher(),
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.settingsSuiteKey: suite,
            ])
        )
        XCTAssertEqual(model.roots.map(\.standardizedFileURL), [initialActive.standardizedFileURL])

        settings.musicRoots = [updatedActiveRoot, updatedArchiveRoot]
        settings.vault.activeRootID = updatedActiveRoot.id
        settings.vault.archiveRootID = updatedArchiveRoot.id
        try store.saveSettings(settings)

        model.applyProjectVaultSettingsChange()
        for _ in 0..<200 where !model.songs.contains(where: { $0.originalFolderName == "Fresh Project" }) {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.roots.map(\.standardizedFileURL), [updatedActive.standardizedFileURL])
        XCTAssertTrue(model.songs.contains { $0.originalFolderName == "Fresh Project" })
    }

    func testVaultArchiveRootIsNotExposedToGenericSongScanner() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-scan-boundary-\(UUID())")
        let active = root.appendingPathComponent("Active")
        let archive = root.appendingPathComponent("Archive")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let activeRoot = StoredMusicRoot(role: .active, url: active)
        let archiveRoot = StoredMusicRoot(role: .archive, url: archive)
        let suite = "ProjectVaultScanBoundaryTests.\(UUID())"
        let store = UserDefaultsSettingsStore(userDefaults: UserDefaults(suiteName: suite)!)
        var settings = AppSettings.default
        settings.musicRoots = [activeRoot, archiveRoot]
        settings.vault = VaultSettings(
            isEnabled: true,
            activeRootID: activeRoot.id,
            archiveRootID: archiveRoot.id,
            rolloutStage: .privateBeta
        )
        try store.saveSettings(settings)

        let model = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: store),
            runtime: MusicHubRuntimeEnvironment(environment: [MusicHubRuntimeEnvironment.settingsSuiteKey: suite])
        )

        XCTAssertEqual(model.roots.map(\.standardizedFileURL), [active.standardizedFileURL])
    }
}
