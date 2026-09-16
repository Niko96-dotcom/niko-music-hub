import AppCore
import XCTest

final class HubFindCommandsTests: XCTestCase {

    func testFindMenuSourceContract() throws {
        let commands = try SourceTestSupport.read("Sources/NikoMusicHub/Commands/HubFindCommands.swift")
        XCTAssertTrue(commands.contains("CommandGroup(after: .pasteboard)"))
        XCTAssertTrue(commands.contains("Button(\"Find\")"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"f\", modifiers: .command)"))
        XCTAssertTrue(commands.contains("Button(\"Jump to Search Field\")"))
        XCTAssertTrue(commands.contains(".keyboardShortcut(\"f\", modifiers: [.command, .option])"))
        XCTAssertTrue(commands.contains("router.execute(.focusArchiveSearch)"))
        XCTAssertTrue(commands.contains("openWindow(id: \"main\")"))

        let app = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")
        XCTAssertTrue(app.contains("HubFindCommands(router:"))

        let field = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/ArchiveSearchTextField.swift")
        XCTAssertTrue(field.contains(".focused($keyboardFocus, equals: .search)"))

        let sidebar = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/ArchiveSidebarView.swift")
        XCTAssertTrue(sidebar.contains(".archiveSearchFocusRequested"))
        XCTAssertTrue(sidebar.contains("keyboardFocus = .search"))

        let board = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/ArchiveBoardView.swift")
        XCTAssertTrue(board.contains(".archiveSearchFocusRequested"))
        XCTAssertTrue(board.contains("keyboardFocus = .search"))
    }
}
