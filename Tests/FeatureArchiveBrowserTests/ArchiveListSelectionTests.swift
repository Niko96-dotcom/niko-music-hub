import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class ArchiveListSelectionTests: XCTestCase {
    func testSelectSongInListDoesNotSetBoardDetail() {
        let song = fixtureSong()
        let viewModel = makeViewModel(songs: [song], viewMode: .list)

        viewModel.selectSong(song)

        XCTAssertEqual(viewModel.selectedSong?.id, song.id)
        XCTAssertEqual(viewModel.viewMode, .list)
        XCTAssertFalse(viewModel.listShowsDetail)
    }

    func testOpenSongDetailInListSetsListShowsDetail() {
        let song = fixtureSong()
        let viewModel = makeViewModel(songs: [song], viewMode: .list)

        viewModel.openSongDetail(song)

        XCTAssertTrue(viewModel.listShowsDetail)
        XCTAssertEqual(viewModel.viewMode, .list)
        XCTAssertEqual(viewModel.selectedSong?.id, song.id)
    }

    func testOpenSongDetailFromBoardSetsBoardDetail() {
        let song = fixtureSong()
        let viewModel = makeViewModel(songs: [song], viewMode: .board)

        viewModel.openSongDetail(song)

        XCTAssertEqual(viewModel.viewMode, .boardDetail)
        XCTAssertEqual(viewModel.selectedSong?.id, song.id)
    }

    private func makeViewModel(songs: [Song], viewMode: ArchiveBrowserViewModel.ArchiveViewMode) -> ArchiveBrowserViewModel {
        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        viewModel.songs = songs
        viewModel.filteredSongs = songs
        viewModel.viewMode = viewMode
        return viewModel
    }

    private func fixtureSong(folder: String = "list-song", title: String = "List Song") -> Song {
        Song(
            folderPath: URL(fileURLWithPath: "/fixture/nmh-051/\(folder)", isDirectory: true),
            originalFolderName: title,
            displayTitle: title
        )
    }
}
