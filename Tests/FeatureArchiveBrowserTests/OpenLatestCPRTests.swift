import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

@MainActor
final class OpenLatestCPRTests: XCTestCase {
    func testLocalVersionOpenUsesChosenFileWithoutChangingMain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("version-open-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "VersionOpenTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var settings = AppSettings()
        settings.musicRoots = [StoredMusicRoot(role: .scanOnly, url: root)]
        try store.saveSettings(settings)
        let versions = try ["Older.cpr", "Alternate.als", "Newest.cpr"].enumerated().map { index, name in
            let url = root.appendingPathComponent(name)
            try Data("fixture project".utf8).write(to: url)
            return ProjectVersion(filePath: url, fileName: name, modifiedAt: Date(timeIntervalSince1970: Double(index)))
        }
        let song = Song(folderPath: root, originalFolderName: "Versions", displayTitle: "Versions", projectVersions: versions, latestCPR: versions[2])
        let model = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: store),
            runtime: MusicHubRuntimeEnvironment(environment: [MusicHubRuntimeEnvironment.dryRunOpenKey: "1"])
        )
        model.songs = [song]
        XCTAssertNil(model.projectOpenBlockReason(for: song))
        for version in versions.prefix(2) {
            try model.openProjectVersion(version, for: song)
            XCTAssertEqual(model.lastDryRunLog, version.filePath.resolvingSymlinksInPath().path)
            XCTAssertEqual(model.songs.first?.effectiveLatestCPR?.id, versions[2].id)
        }
    }

    func testDryRunOpenLogsNeonHookCPR() async throws {
        try CubaseFixtures.ensureGenerated()
        setenv("NIKO_MUSIC_HUB_FIXTURE_ROOT", CubaseFixtures.archiveRoot.path, 1)
        setenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN", "1", 1)
        defer {
            unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
            unsetenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN")
        }

        let context = TestToolContext.make()

        let viewModel = ArchiveBrowserViewModel(context: context)
        await viewModel.scan()

        let neon = try XCTUnwrap(viewModel.songs.first { $0.displayTitle == "Neon Hook" })
        try viewModel.openLatestCPR(for: neon)
        let path = try XCTUnwrap(viewModel.lastDryRunLog)
        XCTAssertTrue(path.contains("Neon Hook"))
        XCTAssertTrue(path.hasSuffix(".cpr"))
    }
}
