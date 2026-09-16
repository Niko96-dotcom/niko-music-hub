import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

final class ArchiveSongSelectionNavigatorTests: XCTestCase {
    func testArrowDownMovesToNextFilteredSong() {
        let songs = fixtureSongs(count: 10)
        let next = ArchiveSongSelectionNavigator.move(
            direction: .down,
            songs: songs,
            selectedID: songs[0].id
        )
        XCTAssertEqual(next?.id, songs[1].id)
        XCTAssertEqual(next?.originalFolderName, "Song 02")
    }

    func testBoardRightArrowMovesToNextColumnFirstSong() {
        let noStatusFirst = fixtureSong("no-status-a", title: "No Status A", status: nil)
        let noStatusSecond = fixtureSong("no-status-b", title: "No Status B", status: nil)
        let prodFirst = fixtureSong("prod-a", title: "Prod A", status: .prod)
        let prodSecond = fixtureSong("prod-b", title: "Prod B", status: .prod)
        let songs = [noStatusFirst, noStatusSecond, prodFirst, prodSecond]

        let next = ArchiveSongSelectionNavigator.moveOnBoard(
            direction: .right,
            songs: songs,
            selectedID: noStatusFirst.id
        )

        XCTAssertEqual(next?.id, prodFirst.id)
        XCTAssertEqual(next?.workflowStatus, .prod)
        XCTAssertEqual(next?.originalFolderName, "Prod A")
    }

    @MainActor
    func testBoardArrowMoveSelectsWithoutOpeningDetailOrPreview() {
        let songs = [
            fixtureSong("idea-a", title: "Idea A", status: .songstarterBeat),
            fixtureSong("idea-b", title: "Idea B", status: .songstarterBeat),
        ]
        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        viewModel.songs = songs
        viewModel.filteredSongs = songs
        viewModel.viewMode = .board
        viewModel.selectSongOnBoard(songs[0])

        viewModel.moveSongSelection(.down)

        XCTAssertEqual(viewModel.selectedSong?.id, songs[1].id)
        XCTAssertEqual(viewModel.viewMode, .board)
    }

    @MainActor
    func testReturnOpensSelectedBoardDetailWithoutStartingPreview() {
        let song = fixtureSong("open-me", title: "Open Me", status: .prod)
        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        viewModel.songs = [song]
        viewModel.filteredSongs = [song]
        viewModel.viewMode = .board
        viewModel.selectSongOnBoard(song)

        viewModel.openSelectedSongDetail()

        XCTAssertEqual(viewModel.viewMode, .boardDetail)
        XCTAssertEqual(viewModel.selectedSong?.id, song.id)
    }

    func testArchiveKeyboardSourceWiresMoveCommandAndReturn() throws {
        let browser = try featureSource("ArchiveBrowserView.swift")
        let sidebar = try featureSource("ArchiveSidebarView.swift")
        let board = try featureSource("ArchiveBoardSongsView.swift")
        XCTAssertTrue(browser.contains(".onMoveCommand"))
        XCTAssertTrue(browser.contains(".onKeyPress(.return)"))
        XCTAssertTrue(browser.contains("openSelectedSongDetail()"))
        XCTAssertTrue(browser.contains(".onKeyPress(.space)"))
        XCTAssertTrue(sidebar.contains(".onMoveCommand"))
        XCTAssertTrue(board.contains(".onMoveCommand"))
        XCTAssertTrue(board.contains("openSongDetail(song)"))
        XCTAssertFalse(board.contains("onOpenDetail: { viewModel.selectSong(song) }"))
    }

    private func featureSource(_ filename: String) throws -> String {
        try String(contentsOfFile: "Sources/FeatureArchiveBrowser/\(filename)", encoding: .utf8)
    }

    private func fixtureSongs(count: Int) -> [Song] {
        (1...count).map { index in
            fixtureSong(
                "song-\(index)",
                title: String(format: "Song %02d", index),
                status: nil
            )
        }
    }

    private func fixtureSong(_ folder: String, title: String, status: ProjectWorkflowStatus?) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: "/fixture/nmh-006/\(folder)", isDirectory: true),
            originalFolderName: title,
            displayTitle: title,
            workflowStatus: status
        )
    }
}
