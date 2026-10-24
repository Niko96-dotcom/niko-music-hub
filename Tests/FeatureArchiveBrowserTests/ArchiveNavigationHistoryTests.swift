import AppCore
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

/// Behavioral reproduction for the navigation claim: restoring a missing
/// detail route falls back to board, and the Combine route publication during
/// restore must leave lastRoute agreeing with the actual route so a later
/// tool switch does not reuse the stale detail token.
@MainActor
final class ArchiveNavigationHistoryTests: XCTestCase {
    func testCatalogRemovalKeepsBoardFallbackAndItsCommandsAvailable() {
        let viewModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        let song = fixtureSong()
        viewModel.applyCatalogEdit(.load([song]))
        viewModel.openSongDetail(song)
        XCTAssertFalse(viewModel.showsBoardPage)

        viewModel.applyCatalogEdit(.load([]))
        XCTAssertNil(viewModel.selectedSong)
        XCTAssertEqual(viewModel.viewMode, .boardDetail)
        XCTAssertTrue(viewModel.showsBoardPage)

        viewModel.viewMode = .analytics
        XCTAssertFalse(viewModel.showsBoardPage)
        viewModel.viewMode = .list
        XCTAssertFalse(viewModel.showsBoardPage)
    }

    func testMissingDetailFallsBackToBoardAndLastRouteAgrees() {
        let context = TestToolContext.make()
        let viewModel = ArchiveBrowserViewModel(context: context)
        let history = context.navigationHistory
        let archiveID = ToolFeatureID.archiveBrowser
        let song = fixtureSong()
        viewModel.applyCatalogEdit(.load([song]))
        viewModel.filteredSongs = [song]
        viewModel.selectedSong = nil
        viewModel.viewMode = .board

        let entriesBefore = history.entries.count
        let indexBefore = history.index

        // Same-value edge: the view model is already on board, so the
        // fallback assignment does not visibly change the page.
        history.restore(HubNavigationEntry(toolID: archiveID, route: "detail:missing-song-id"))

        XCTAssertEqual(viewModel.viewMode, .board)
        XCTAssertEqual(viewModel.navigationRoute, "board")
        XCTAssertEqual(history.lastRoute(for: archiveID), "board")
        XCTAssertEqual(history.entries.count, entriesBefore, "restore must not append entries")
        XCTAssertEqual(history.index, indexBefore)
    }

    func testMissingDetailFromListFallsBackToBoardAndLastRouteAgrees() {
        let context = TestToolContext.make()
        let viewModel = ArchiveBrowserViewModel(context: context)
        let history = context.navigationHistory
        let archiveID = ToolFeatureID.archiveBrowser
        let song = fixtureSong()
        viewModel.applyCatalogEdit(.load([song]))
        viewModel.filteredSongs = [song]
        viewModel.selectedSong = song
        viewModel.viewMode = .list
        XCTAssertEqual(history.lastRoute(for: archiveID), "list:\(song.id)")

        history.restore(HubNavigationEntry(toolID: archiveID, route: "detail:missing-song-id"))

        XCTAssertEqual(viewModel.viewMode, .board)
        XCTAssertEqual(viewModel.navigationRoute, "board")
        XCTAssertEqual(history.lastRoute(for: archiveID), "board")
    }

    func testRestoredBoardListAndSubsequentToolSwitchUsesActualRoute() {
        let context = TestToolContext.make()
        let viewModel = ArchiveBrowserViewModel(context: context)
        let history = context.navigationHistory
        let archiveID = ToolFeatureID.archiveBrowser
        let song = fixtureSong()
        viewModel.applyCatalogEdit(.load([song]))
        viewModel.filteredSongs = [song]
        viewModel.selectedSong = nil
        viewModel.viewMode = .board

        history.restore(HubNavigationEntry(toolID: archiveID, route: "list:\(song.id)"))
        XCTAssertEqual(viewModel.viewMode, .list)
        XCTAssertEqual(viewModel.navigationRoute, "list:\(song.id)")
        XCTAssertEqual(history.lastRoute(for: archiveID), "list:\(song.id)")

        history.restore(HubNavigationEntry(toolID: archiveID, route: "list:missing-song-id"))
        XCTAssertEqual(viewModel.viewMode, .list)
        XCTAssertEqual(viewModel.navigationRoute, "list")
        XCTAssertEqual(history.lastRoute(for: archiveID), "list")

        history.restore(HubNavigationEntry(toolID: archiveID, route: "board"))
        XCTAssertEqual(viewModel.viewMode, .board)
        XCTAssertEqual(history.lastRoute(for: archiveID), "board")

        // Fallback then tool switch: the new archive entry must carry the
        // actual board route, not the stale detail token.
        history.restore(HubNavigationEntry(toolID: archiveID, route: "detail:missing-song-id"))
        XCTAssertEqual(history.lastRoute(for: archiveID), "board")

        history.record(toolID: "bpm-tapper")
        history.record(toolID: archiveID)

        XCTAssertEqual(history.current?.toolID, archiveID)
        XCTAssertEqual(history.current?.route, "board")
    }

    func testBackForwardPreservedAcrossFallbackRestore() {
        let context = TestToolContext.make()
        let viewModel = ArchiveBrowserViewModel(context: context)
        let history = context.navigationHistory
        let archiveID = ToolFeatureID.archiveBrowser
        let song = fixtureSong()
        viewModel.applyCatalogEdit(.load([song]))
        viewModel.filteredSongs = [song]
        viewModel.selectedSong = nil
        viewModel.viewMode = .board
        history.record(toolID: archiveID, route: "board")

        viewModel.selectedSong = song
        viewModel.viewMode = .boardDetail
        XCTAssertEqual(history.lastRoute(for: archiveID), "detail:\(song.id)")

        let back = history.goBack()
        XCTAssertEqual(back?.route, "board")
        history.restore(back!)
        XCTAssertEqual(viewModel.viewMode, .board)
        XCTAssertEqual(history.lastRoute(for: archiveID), "board")
        XCTAssertTrue(history.canGoForward)

        // The song leaves the catalog while the board shows; the forward detail
        // entry is now stale. (Removed while its detail was open, the catalog
        // edit would clear the selection first, as a rescan does.)
        viewModel.applyCatalogEdit(.load([]))
        XCTAssertTrue(history.canGoForward)

        let entriesBeforeForwardRestore = history.entries.count
        let forward = history.goForward()
        XCTAssertEqual(forward?.route, "detail:\(song.id)")
        history.restore(forward!)
        XCTAssertEqual(viewModel.viewMode, .board, "missing detail must fall back to board")
        XCTAssertEqual(viewModel.navigationRoute, "board")
        XCTAssertEqual(history.lastRoute(for: archiveID), "board")
        XCTAssertEqual(history.entries.count, entriesBeforeForwardRestore, "restore must not append entries")
        XCTAssertTrue(history.canGoBack)

        history.record(toolID: "bpm-tapper")
        history.record(toolID: archiveID)
        XCTAssertEqual(history.current?.route, "board")
    }

    /// Back from the detail (its Board button and Esc call `showBoard()`): the
    /// board shows, the song stays highlighted, and the route is `board`.
    func testShowBoardFromTheDetailKeepsTheSelectionAndRecordsTheBoard() {
        let context = TestToolContext.make()
        let viewModel = ArchiveBrowserViewModel(context: context)
        let song = fixtureSong()
        viewModel.applyCatalogEdit(.load([song]))
        viewModel.openSongDetail(song)
        XCTAssertEqual(context.navigationHistory.lastRoute(for: ToolFeatureID.archiveBrowser), "detail:\(song.id)")

        viewModel.showBoard()

        XCTAssertEqual(viewModel.viewMode, .board)
        XCTAssertEqual(viewModel.selectedSong, song)
        XCTAssertEqual(context.navigationHistory.lastRoute(for: ToolFeatureID.archiveBrowser), "board")
    }

    func testShowBoardFromAnalyticsRecordsTheBoardAndOnTheBoardAddsNoEntry() {
        let context = TestToolContext.make()
        let viewModel = ArchiveBrowserViewModel(context: context)
        let history = context.navigationHistory
        viewModel.applyCatalogEdit(.load([fixtureSong()]))
        viewModel.showAnalytics()
        XCTAssertEqual(history.lastRoute(for: ToolFeatureID.archiveBrowser), "analytics")

        viewModel.showBoard()
        XCTAssertEqual(viewModel.viewMode, .board)
        XCTAssertEqual(history.lastRoute(for: ToolFeatureID.archiveBrowser), "board")

        let entries = history.entries.count
        viewModel.showBoard()
        XCTAssertEqual(history.entries.count, entries, "the board again is not a new history entry")
    }

    private func fixtureSong() -> Song {
        Song(
            folderPath: URL(fileURLWithPath: "/fixture/nav-history/Nav Song", isDirectory: true),
            originalFolderName: "Nav Song",
            displayTitle: "Nav Song"
        )
    }
}
