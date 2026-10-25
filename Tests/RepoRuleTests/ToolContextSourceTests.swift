import XCTest

final class ToolContextSourceTests: XCTestCase {
    /// The archive view model needs a context before the feature list and the
    /// registry exist. Launch warnings, which a registry failure adds to, go to
    /// their only reader, the shell, so one context serves the whole launch.
    func testCompositionBuildsOneContextAndHandsLaunchWarningsToTheShell() throws {
        let composition = SourceLex.stripped(try SourceTestSupport.read("Sources/NikoMusicHub/AppComposition.swift"))
        XCTAssertEqual(composition.components(separatedBy: "ToolContext(").count - 1, 1)
        XCTAssertTrue(composition.contains("persistenceIssues: persistenceIssues"))

        let shell = SourceLex.stripped(try SourceTestSupport.read("Sources/NikoMusicHub/AppShell/AppShellView.swift"))
        XCTAssertTrue(shell.contains("persistenceIssues: [PersistenceIssue]"))
        XCTAssertFalse(shell.contains("context.persistenceIssues"))
    }
}
