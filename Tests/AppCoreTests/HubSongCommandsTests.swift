import XCTest

final class HubSongCommandsTests: XCTestCase {

    func testSongMenuSourceContract() throws {
        let commands = try SourceTestSupport.read("Sources/NikoMusicHub/Commands/HubSongCommands.swift")
        XCTAssertTrue(commands.contains("CommandMenu(\"Song\")"))
        XCTAssertTrue(commands.contains("SongItemCommandCopy.previewTitle(isPlaying:"))
        XCTAssertTrue(commands.contains("Space when the archive is focused"))
        XCTAssertFalse(commands.contains(".keyboardShortcut(.space"))
        XCTAssertFalse(commands.contains("Play/Pause Preview"))
        XCTAssertTrue(commands.contains("Button(\"Open Preview\")"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"p\", modifiers: [])"))
        XCTAssertTrue(commands.contains("SongWorkflowActions.songMenuTitle"))
        XCTAssertTrue(commands.contains("applyWorkflowStatus"))
        XCTAssertTrue(commands.contains("allowsWorkflowMutation"))
        XCTAssertTrue(commands.contains("SongItemCommandCopy.openProject"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"o\", modifiers: .command)"))
        XCTAssertTrue(commands.contains("SongItemCommandCopy.revealInFinder"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"r\", modifiers: .command)"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"f\", modifiers: [])"))
        XCTAssertTrue(commands.contains("Button(\"Show Versions\")"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"d\", modifiers: [])"))
        XCTAssertTrue(commands.contains("isPreviewPlaying"))

        let openRange = try XCTUnwrap(commands.range(of: "SongItemCommandCopy.openProject"))
        let playRange = try XCTUnwrap(commands.range(of: "SongItemCommandCopy.previewTitle"))
        XCTAssertLessThan(openRange.lowerBound, playRange.lowerBound)

        let app = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")
        XCTAssertTrue(app.contains("HubSongCommands("))
        let toolsRange = try XCTUnwrap(app.range(of: "HubToolsCommands("))
        let songRange = try XCTUnwrap(app.range(of: "HubSongCommands("))
        XCTAssertLessThan(toolsRange.lowerBound, songRange.lowerBound)

        let find = try SourceTestSupport.read("Sources/NikoMusicHub/Commands/HubFindCommands.swift")
        XCTAssertTrue(find.contains(".keyboardShortcut(\"f\", modifiers: .command)"))

        let browser = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift")
        // The pane keeps real focus (NMH-006 Space/arrows; Option-arrows pass the
        // archive arrow monitor through to Song skip, NMH-034) but must not draw
        // AppKit's system-blue ring around the whole tool. The quiet
        // Palette.focus ring stays as the affordance for keyboard-navigation
        // users only (owner decision 2026-09-17).
        XCTAssertTrue(browser.contains(".focusEffectDisabled()"))
        XCTAssertTrue(browser.contains(".focusable(true)"))
        XCTAssertFalse(browser.contains(".focusable(interactions: .edit)"))
        XCTAssertTrue(browser.contains("HubDesignSystem.Palette.focus"))
        XCTAssertTrue(browser.contains("NSApp.isFullKeyboardAccessEnabled"))
        XCTAssertTrue(browser.contains("onKeyPress(\"o\")"))
        XCTAssertTrue(browser.contains("onKeyPress(\"p\")"))
        XCTAssertTrue(browser.contains("onKeyPress(\"f\")"))
        XCTAssertTrue(browser.contains("onKeyPress(\"d\")"))
        XCTAssertTrue(browser.contains("onKeyPress(.space)"))
        XCTAssertTrue(browser.contains(".focusedValue(\\."))
        XCTAssertTrue(browser.contains("archiveShowSongVersions"))


        let policy = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/ArchiveShortcutFocusPolicy.swift")
        XCTAssertTrue(policy.contains(".option, .command, .control"))

        let detail = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/SongDetailView.swift")
        XCTAssertTrue(detail.contains("archiveShowSongVersions"))
        XCTAssertTrue(detail.contains("workspaceTab = .versions"))
    }
}
