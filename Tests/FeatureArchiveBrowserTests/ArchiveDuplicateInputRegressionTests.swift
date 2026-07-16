import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

@MainActor
final class ArchiveDuplicateInputRegressionTests: XCTestCase {
    func testRootDisplayPolicyCanonicalizesDuplicateURLs() {
        let root = URL(fileURLWithPath: "/tmp/archive-root", isDirectory: true)

        XCTAssertEqual(ArchiveRootDisplayPolicy.storedRoots(from: [root, root]), [root.standardizedFileURL])
    }

    func testFullScanAndScanHostCollapseDuplicateSongIDs() {
        let context = TestToolContext.make()
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/duplicate-song", isDirectory: true),
            originalFolderName: "Duplicate Song",
            displayTitle: "Duplicate Song"
        )
        let coordinator = ArchiveCatalogCoordinator(
            archiveIndexStore: nil,
            songMetadataStore: nil,
            collaboratorStore: nil,
            diagnostics: context.diagnostics
        )
        let applied = coordinator.applyFullScanResult(
            result: ScanResult(songs: [song, song]),
            roots: [URL(fileURLWithPath: "/tmp")],
            collaborators: [],
            scannedAt: Date()
        )
        XCTAssertEqual(applied.songs.count, 1)

        let model = ArchiveBrowserViewModel(
            context: context,
            runtime: MusicHubRuntimeEnvironment(environment: [
                MusicHubRuntimeEnvironment.settingsSuiteKey: "ArchiveDuplicateInputRegressionTests.\(UUID())"
            ])
        )
        model.songs = [song, song]
        model.applyCatalogScanUpdate(applied, roots: [URL(fileURLWithPath: "/tmp")])

        XCTAssertEqual(model.songs.count, 1)
        XCTAssertEqual(model.songs.first?.id, song.id)
    }
}
