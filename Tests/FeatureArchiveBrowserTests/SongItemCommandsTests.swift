import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

final class SongItemCommandsTests: XCTestCase {
    func testMenuOrder() {
        XCTAssertEqual(
            SongItemCommand.menuOrder,
            [.openProject, .playPreview, .revealInFinder, .workflowStatus]
        )
        XCTAssertEqual(
            SongItemCommand.allCases,
            [.openProject, .playPreview, .pausePreview, .revealInFinder, .workflowStatus]
        )
        XCTAssertFalse(
            SongItemCommand.menuOrder.contains(.pausePreview),
            "Pause occupies the Play Preview slot rather than a separate menu row"
        )
    }

    func testPlayTitleDependsOnSession() {
        XCTAssertEqual(SongItemCommandCopy.previewTitle(isPlaying: false), "Play Preview")
        XCTAssertEqual(SongItemCommandCopy.previewTitle(isPlaying: true), "Pause Preview")
        XCTAssertEqual(SongItemCommandCopy.openProject, "Open Project")
        XCTAssertEqual(SongItemCommandCopy.playPreview, "Play Preview")
        XCTAssertEqual(SongItemCommandCopy.pausePreview, "Pause Preview")
        XCTAssertEqual(SongItemCommandCopy.revealInFinder, "Reveal in Finder")
    }

    func testListBoardDetailAndSongMenuShareTheSameCommands() throws {
        let commandsView = try featureSource("SongItemCommands.swift")
        let list = try featureSource("SongCardView.swift")
        let board = try featureSource("ArchiveBoardView.swift")
        let detail = try featureSource("SongDetailView.swift")
        let songMenu = try String(
            contentsOfFile: "Sources/NikoMusicHub/Commands/HubSongCommands.swift",
            encoding: .utf8
        )

        XCTAssertTrue(commandsView.contains("SongItemCommandCopy.openProject"))
        XCTAssertTrue(commandsView.contains("SongItemCommandCopy.previewTitle(isPlaying:"))
        XCTAssertTrue(commandsView.contains("SongItemCommandCopy.revealInFinder"))
        XCTAssertTrue(commandsView.contains("Divider()"))
        XCTAssertTrue(commandsView.contains("SongWorkflowActions.songMenuTitle"))
        XCTAssertTrue(commandsView.contains("SongWorkflowContextMenu("))
        XCTAssertFalse(commandsView.contains(".keyboardShortcut("), "HIG: shortcuts belong on the Song menu, not Control-click")

        XCTAssertTrue(list.contains("SongItemCommands("), "List cards must share the full item menu")
        XCTAssertTrue(board.contains("SongItemCommands("), "Board cards must share the full item menu")
        XCTAssertFalse(list.contains("Convert main preview"))
        XCTAssertFalse(board.contains("Hide song from browse"))

        XCTAssertTrue(detail.contains("SongItemCommands("))
        XCTAssertTrue(detail.contains("showsWorkflowStatus: false"))
        XCTAssertTrue(detail.contains("Convert main preview"))
        XCTAssertTrue(detail.contains("Hide song from browse"))
        XCTAssertTrue(detail.contains("More song actions"))

        let openRange = try XCTUnwrap(songMenu.range(of: "SongItemCommandCopy.openProject"))
        let playRange = try XCTUnwrap(songMenu.range(of: "SongItemCommandCopy.previewTitle"))
        let revealRange = try XCTUnwrap(songMenu.range(of: "SongItemCommandCopy.revealInFinder"))
        XCTAssertLessThan(openRange.lowerBound, playRange.lowerBound)
        XCTAssertLessThan(playRange.lowerBound, revealRange.lowerBound)
        XCTAssertTrue(songMenu.contains("SongWorkflowActions.songMenuTitle"))
        XCTAssertFalse(songMenu.contains("Play/Pause Preview"))
    }

    private func featureSource(_ filename: String) throws -> String {
        try String(contentsOfFile: "Sources/FeatureArchiveBrowser/\(filename)", encoding: .utf8)
    }
}
