import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

@MainActor
final class ProjectVaultScanBoundaryTests: XCTestCase {
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
