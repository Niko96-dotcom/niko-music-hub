import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class ArchiveListSelectionTests: XCTestCase {
    func testSelectSongInListDoesNotSetBoardDetail() {
        let song = fixtureSong()
        let viewModel = makeViewModel(songs: [song], viewMode: .list)

        viewModel.selectSong(song)

        XCTAssertEqual(viewModel.page.selectedSong?.id, song.id)
        XCTAssertEqual(viewModel.page.viewMode, .list)
        XCTAssertFalse(viewModel.page.listShowsDetail)
    }

    func testOpenSongDetailInListSetsListShowsDetail() {
        let song = fixtureSong()
        let viewModel = makeViewModel(songs: [song], viewMode: .list)

        viewModel.openSongDetail(song)

        XCTAssertTrue(viewModel.page.listShowsDetail)
        XCTAssertEqual(viewModel.page.viewMode, .list)
        XCTAssertEqual(viewModel.page.selectedSong?.id, song.id)
    }

    func testOpenSongDetailFromBoardSetsBoardDetail() {
        let song = fixtureSong()
        let viewModel = makeViewModel(songs: [song], viewMode: .board)

        viewModel.openSongDetail(song)

        XCTAssertEqual(viewModel.page.viewMode, .boardDetail)
        XCTAssertEqual(viewModel.page.selectedSong?.id, song.id)
    }

    private func makeViewModel(songs: [Song], viewMode: ArchiveViewMode) -> ArchiveBrowserViewModel {
        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        viewModel.applyCatalogEdit(.load(songs))
        if viewMode == .list {
            viewModel.setBrowseLayout(list: true)
        }
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
