import XCTest

final class HubSongCommandsTests: XCTestCase {

    func testSongMenuSourceContract() throws {
        let commands = try SourceTestSupport.read("Sources/NikoMusicHub/Commands/HubSongCommands.swift")
        XCTAssertTrue(commands.contains("CommandMenu(\"Song\")"))
        XCTAssertTrue(commands.contains("Button(\"Play/Pause Preview\")"))
        XCTAssertTrue(commands.contains("Space when the archive is focused"))
        XCTAssertFalse(commands.contains(".keyboardShortcut(.space"))
        XCTAssertTrue(commands.contains("Button(\"Open Preview\")"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"p\", modifiers: [])"))
        XCTAssertTrue(commands.contains("Button(\"Open Project\")"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"o\", modifiers: .command)"))
        XCTAssertTrue(commands.contains("Button(\"Reveal in Finder\")"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"r\", modifiers: .command)"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"f\", modifiers: [])"))
        XCTAssertTrue(commands.contains("Button(\"Show Versions\")"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"d\", modifiers: [])"))

        let app = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")
        XCTAssertTrue(app.contains("HubSongCommands("))
        let toolsRange = try XCTUnwrap(app.range(of: "HubToolsCommands("))
        let songRange = try XCTUnwrap(app.range(of: "HubSongCommands("))
        XCTAssertLessThan(toolsRange.lowerBound, songRange.lowerBound)

        let find = try SourceTestSupport.read("Sources/NikoMusicHub/Commands/HubFindCommands.swift")
        XCTAssertTrue(find.contains(".keyboardShortcut(\"f\", modifiers: .command)"))

        let browser = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift")
        XCTAssertFalse(browser.contains(".focusEffectDisabled()"))
        XCTAssertTrue(browser.contains(".focusable(interactions: .edit)"))
        XCTAssertTrue(browser.contains("HubDesignSystem.Palette.focus"))
        XCTAssertTrue(browser.contains("onKeyPress(\"o\")"))
        XCTAssertTrue(browser.contains("onKeyPress(\"p\")"))
        XCTAssertTrue(browser.contains("onKeyPress(\"f\")"))
        XCTAssertTrue(browser.contains("onKeyPress(\"d\")"))
        XCTAssertTrue(browser.contains("onKeyPress(.space)"))
        XCTAssertTrue(browser.contains(".focusedValue(\\."))
        XCTAssertTrue(browser.contains("archiveShowSongVersions"))

        let detail = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/SongDetailView.swift")
        XCTAssertTrue(detail.contains("archiveShowSongVersions"))
        XCTAssertTrue(detail.contains("workspaceTab = .versions"))
    }
}
