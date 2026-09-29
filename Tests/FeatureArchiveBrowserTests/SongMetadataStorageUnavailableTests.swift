import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// A production metadata store that failed to open must fail closed: edits are
/// refused with a visible warning instead of looking saved and vanishing on the
/// next rescan. The deliberate in-memory mode (no store, not flagged) keeps its
/// existing behavior.
@MainActor
final class SongMetadataStorageUnavailableTests: XCTestCase {
    override func setUp() {
        super.setUp()
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        unsetenv("NIKO_MUSIC_HUB_DEV_ARCHIVE_ROOT")
    }

    private func makeFixture() throws -> (root: URL, song: Song) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nmh-storage-unavailable-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Night Drive", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let song = Song(folderPath: folder, originalFolderName: "Night Drive", displayTitle: "Night Drive")
        return (root, song)
    }

    private func makeViewModel(
        song: Song,
        root: URL,
        storageUnavailable: Bool
    ) async -> ArchiveBrowserViewModel {
        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: nil,
            songMetadataStorageUnavailable: storageUnavailable,
            archiveRootWatcher: NoopArchiveRootWatcher(),
            scanOverride: { _ in ScanResult(songs: [song]) }
        )
        viewModel.roots = [root]
        await viewModel.scan()
        return viewModel
    }

    func testUnavailableStorageStillBrowsesAndScans() async throws {
        let (root, song) = try makeFixture()
        let viewModel = await makeViewModel(song: song, root: root, storageUnavailable: true)

        XCTAssertEqual(viewModel.songs.map(\.id), [song.id])
    }

    func testUnavailableStorageRefusesTitleEditWithVisibleWarning() async throws {
        let (root, song) = try makeFixture()
        let viewModel = await makeViewModel(song: song, root: root, storageUnavailable: true)
        let live = try XCTUnwrap(viewModel.songs.first)

        viewModel.updateVirtualTitle(for: live, title: "Renamed")

        let after = try XCTUnwrap(viewModel.songs.first)
        XCTAssertNil(after.virtualTitle, "a refused edit must not change the visible song")
        XCTAssertEqual(after.effectiveDisplayTitle, "Night Drive")
        XCTAssertTrue(
            viewModel.statusMessage?.contains(SongMetadataIntegrityCopy.storageUnavailable) == true,
            "got: \(viewModel.statusMessage ?? "nil")"
        )
        XCTAssertNotNil(viewModel.catalog.metadataEditBlockWarning(for: song.id))
    }

    func testUnavailableStorageRefusesWorkflowStatusEdit() async throws {
        let (root, song) = try makeFixture()
        let viewModel = await makeViewModel(song: song, root: root, storageUnavailable: true)
        let live = try XCTUnwrap(viewModel.songs.first)

        viewModel.updateWorkflowStatus(for: live, status: .prod)

        XCTAssertNil(viewModel.songs.first?.workflowStatus)
        XCTAssertTrue(
            viewModel.statusMessage?.contains(SongMetadataIntegrityCopy.storageUnavailable) == true,
            "got: \(viewModel.statusMessage ?? "nil")"
        )
    }

    func testUnavailableStorageWorkflowStatusEditRegistersNoUndo() async throws {
        let (root, song) = try makeFixture()
        let viewModel = await makeViewModel(song: song, root: root, storageUnavailable: true)
        let undoManager = UndoManager()
        viewModel.bindInjectedUndoManager(undoManager)
        let live = try XCTUnwrap(viewModel.songs.first)

        viewModel.updateWorkflowStatus(for: live, status: .prod)

        XCTAssertNil(viewModel.songs.first?.workflowStatus)
        XCTAssertFalse(undoManager.canUndo, "a refused status change must not be undoable")
    }

    func testUnavailableStoragePersistNeverReportsSuccess() throws {
        let (_, song) = try makeFixture()
        let catalog = ArchiveCatalogCoordinator(
            archiveIndexStore: nil,
            songMetadataStore: nil,
            songMetadataStorageUnavailable: true,
            collaboratorStore: nil,
            diagnostics: CapturingDiagnostics()
        )

        XCTAssertEqual(catalog.persistUserMetadata(for: [song]), SongMetadataIntegrityCopy.storageUnavailable)
        XCTAssertNil(catalog.persistUserMetadata(for: []), "nothing to persist is not a failure")
    }

    func testInMemoryDefaultStillAcceptsEdits() async throws {
        let (root, song) = try makeFixture()
        let viewModel = await makeViewModel(song: song, root: root, storageUnavailable: false)
        let live = try XCTUnwrap(viewModel.songs.first)

        viewModel.updateVirtualTitle(for: live, title: "Renamed")
        let live2 = try XCTUnwrap(viewModel.songs.first)
        viewModel.updateWorkflowStatus(for: live2, status: .prod)

        let after = try XCTUnwrap(viewModel.songs.first)
        XCTAssertEqual(after.virtualTitle, "Renamed")
        XCTAssertEqual(after.workflowStatus, .prod)
        XCTAssertNil(viewModel.catalog.metadataEditBlockWarning(for: song.id))
    }
}
