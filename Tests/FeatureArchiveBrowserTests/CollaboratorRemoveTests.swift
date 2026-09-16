import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

/// NMH-090: the address book can remove collaborators only after confirmation.
/// Removing a name deletes the row and unassigns it from songs; files untouched.
@MainActor
final class CollaboratorRemoveTests: XCTestCase {
    func testRemoveDeletesRowAndSongIDs() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collaborator-remove-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let collaboratorStore = try SQLiteCollaboratorStore(databaseURL: databaseURL)

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            collaboratorStore: collaboratorStore
        )
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))
        let song = Song(
            folderPath: FileManager.default.temporaryDirectory
                .appendingPathComponent("collab-remove-song-\(UUID().uuidString)", isDirectory: true),
            originalFolderName: "Fixture Song",
            displayTitle: "Fixture Song"
        )
        viewModel.scannedSongs = [song]
        viewModel.songs = [song]
        viewModel.assignCollaborators(to: song, collaboratorIDs: [jamie.id])
        XCTAssertEqual(viewModel.songs.first?.collaboratorIDs, [jamie.id])

        viewModel.requestRemoveCollaborator(jamie)
        XCTAssertEqual(viewModel.pendingCollaboratorRemoval?.id, jamie.id)
        // Request alone must not delete: row and assignment stay.
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(viewModel.songs.first?.collaboratorIDs, [jamie.id])

        viewModel.confirmRemoveCollaborator()

        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertTrue(viewModel.collaborators.isEmpty)
        XCTAssertEqual(viewModel.songs.first?.collaboratorIDs, [])
        XCTAssertTrue(try collaboratorStore.loadAll().isEmpty)
    }

    func testCancelLeavesRowAndSongIDs() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collaborator-remove-cancel-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let collaboratorStore = try SQLiteCollaboratorStore(databaseURL: databaseURL)

        let viewModel = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            collaboratorStore: collaboratorStore
        )
        let jamie = try XCTUnwrap(viewModel.upsertCollaborator(name: "Jamie"))
        let song = Song(
            folderPath: FileManager.default.temporaryDirectory
                .appendingPathComponent("collab-remove-cancel-song-\(UUID().uuidString)", isDirectory: true),
            originalFolderName: "Fixture Song",
            displayTitle: "Fixture Song"
        )
        viewModel.scannedSongs = [song]
        viewModel.songs = [song]
        viewModel.assignCollaborators(to: song, collaboratorIDs: [jamie.id])

        viewModel.requestRemoveCollaborator(jamie)
        viewModel.cancelRemoveCollaborator()

        XCTAssertNil(viewModel.pendingCollaboratorRemoval)
        XCTAssertEqual(viewModel.collaborators.map(\.id), [jamie.id])
        XCTAssertEqual(viewModel.songs.first?.collaboratorIDs, [jamie.id])
        XCTAssertEqual(try collaboratorStore.loadAll().map(\.id), [jamie.id])
    }
}
