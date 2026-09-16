import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

final class ArchiveBoardWorkflowAccessTests: XCTestCase {
    func testBoardCardExposesMoveAccessibilityActionNames() {
        XCTAssertEqual(
            SongWorkflowActions.accessibilityActionNames,
            [
                "Move to Songstarter/Beat",
                "Move to Song",
                "Move to Session Prod",
                "Move to Prod",
                "Move to Waiting Feedback",
                "Move to Feedback Todo",
                "Move to Done",
                "Clear Status",
            ]
        )
        XCTAssertEqual(SongWorkflowActions.clearStatusMenuTitle, "No Status")
        XCTAssertEqual(SongWorkflowActions.songMenuTitle, "Move to…")
        XCTAssertEqual(SongWorkflowActions.moveAccessibilityName(for: .prod), "Move to Prod")
    }

    func testBoardCardSourceExposesContextMenuDragAndMoveActions() throws {
        let board = try featureSource("ArchiveBoardView.swift")
        let songs = try featureSource("ArchiveBoardSongsView.swift")
        let menu = try featureSource("SongWorkflowContextMenu.swift")
        let list = try featureSource("SongCardView.swift")

        XCTAssertTrue(board.contains("SongItemCommands"), "Board card must share the list item context menu")
        XCTAssertTrue(board.contains("SongWorkflowAccessibilityActions"), "Board card must expose named Move to… VoiceOver actions")
        XCTAssertTrue(board.contains("ArchiveBoardCardDragModifier"), "Drag onto columns must remain")
        XCTAssertTrue(board.contains(".draggable(songID)"), "Drag payload stays the song id")
        XCTAssertTrue(
            songs.contains("applyWorkflowStatus"),
            "Board card workflow changes must use applyWorkflowStatus so Done confirms (NMH-003)"
        )
        XCTAssertTrue(menu.contains("Button(SongWorkflowActions.clearStatusMenuTitle)"))
        XCTAssertTrue(menu.contains("ForEach(ProjectWorkflowStatus.allCases"))
        XCTAssertTrue(list.contains("SongItemCommands"), "List menu must keep Open / Play / Reveal / status")
        XCTAssertFalse(list.contains("Button(\"No Status\")"), "List must not keep a parallel hardcoded status menu")
    }

    func testSongMenuSourceExposesMoveToSubmenu() throws {
        let commands = try String(
            contentsOfFile: "Sources/NikoMusicHub/Commands/HubSongCommands.swift",
            encoding: .utf8
        )
        let focus = try featureSource("ArchiveShortcutFocusPolicy.swift")
        let browser = try featureSource("ArchiveBrowserView.swift")
        XCTAssertTrue(commands.contains("SongWorkflowActions.songMenuTitle"))
        XCTAssertTrue(commands.contains("applyWorkflowStatus"))
        XCTAssertTrue(focus.contains("allowsWorkflowMutation"))
        XCTAssertTrue(focus.contains("applyWorkflowStatus"))
        XCTAssertTrue(browser.contains("performApplyWorkflowStatus"))
        XCTAssertTrue(browser.contains("applyWorkflowStatus(status, for: song)"))
    }

    private func featureSource(_ filename: String) throws -> String {
        try String(contentsOfFile: "Sources/FeatureArchiveBrowser/\(filename)", encoding: .utf8)
    }
}
