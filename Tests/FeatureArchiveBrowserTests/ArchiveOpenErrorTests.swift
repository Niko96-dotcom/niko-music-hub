import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// NMH-049: open/scan failures surface nearby recovery, not only the footer bar.
/// Fixture-only; never touches real music data.
@MainActor
final class ArchiveOpenErrorTests: XCTestCase {
    func testOpenMissingPathSetsOpenErrorNotOnlyStatus() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nmh-049-open-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "ArchiveOpenErrorTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(userDefaults: defaults, key: "settings")
        var settings = AppSettings()
        settings.musicRoots = [StoredMusicRoot(role: .scanOnly, url: root)]
        try store.saveSettings(settings)

        // CPR path is never created: resolving it must throw pathDoesNotExist.
        let missingURL = root.appendingPathComponent("Missing.cpr")
        let version = ProjectVersion(filePath: missingURL, fileName: "Missing.cpr", modifiedAt: Date(timeIntervalSince1970: 0))
        let song = Song(
            folderPath: root,
            originalFolderName: "Missing Song",
            displayTitle: "Missing Song",
            projectVersions: [version],
            latestCPR: version
        )
        let model = ArchiveBrowserViewModel(
            context: TestToolContext.make(settingsStore: store),
            runtime: MusicHubRuntimeEnvironment(environment: [MusicHubRuntimeEnvironment.dryRunOpenKey: "1"])
        )
        model.songs = [song]

        XCTAssertThrowsError(try model.openLatestCPR(for: song))
        XCTAssertEqual(model.openError, ArchiveOpenErrorCopy.missingProject)
        XCTAssertNotNil(model.statusMessage)
    }

    func testScanFailureSetsScanError() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.applyScanFailure(
            NSError(
                domain: "NMH049",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "unreadable fixture root"]
            )
        )
        XCTAssertEqual(model.scanError, ArchiveOpenErrorCopy.scanBody)
        XCTAssertTrue(model.statusMessage?.contains("Scan failed") == true)
    }
}
