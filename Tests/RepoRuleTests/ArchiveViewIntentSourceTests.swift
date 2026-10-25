import XCTest

/// Archive views state intent; `ArchivePageModel` owns the page. Views that wrote `viewMode` themselves
/// drifted from the model's own rules before (477f9ae fixed four view copies of `showsBoardPage`). The
/// setters are `private(set)` in `ArchivePageModel`, so the compiler refuses a write elsewhere; this test
/// keeps that file the one writer if the setters ever open up.
/// AGENTS.md row "Archive page"; docs/architecture.md § Archive page state.
final class ArchiveViewIntentSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Archive page",
        why: "Views that wrote the page themselves drifted from the page model's rules",
        see: "AGENTS.md row \"Archive page\"; docs/architecture.md § Archive page state",
        fix: "Call an intent (openSongDetail, showBoard, setBrowseLayout(list:), showAnalytics, clearSelection, …)"
    )

    private static let pageWrite = SourceTree.regex(#"\b(?:viewMode|listShowsDetail)\s*=(?!=)"#)

    func testOnlyThePageModelWritesThePage() {
        let files = SourceTree.swiftFiles(under: "Sources/FeatureArchiveBrowser/", atLeast: 50)
            .filter { !$0.hasSuffix("/ArchivePageModel.swift") }
        Self.rule.check(files.flatMap { SourceTree.matches(Self.pageWrite, in: SourceTree.read($0, .code), path: $0) }, "writes the page")
    }

    /// The detector must catch a view write and leave reads and declarations alone.
    func testPageWriteDetector() {
        func hits(_ line: String) -> Int { SourceTree.matches(Self.pageWrite, in: SourceLex.stripped(line)).count }
        XCTAssertEqual(hits("viewModel.page.viewMode = .board"), 1)
        XCTAssertEqual(hits("viewModel.page.listShowsDetail = false"), 1)
        XCTAssertEqual(hits("onOpenListView: { viewModel.page.viewMode = .list }"), 1)
        XCTAssertEqual(hits("if viewModel.page.viewMode == .board {"), 0)
        XCTAssertEqual(hits("guard viewMode != .list else { return }"), 0)
        XCTAssertEqual(hits("@Published private(set) var viewMode: ArchiveViewMode = .board {"), 0)
        XCTAssertEqual(hits("Self.navigationRoute(viewMode: viewMode, songID: nil)"), 0)
        XCTAssertEqual(hits("// viewModel.page.viewMode = .board"), 0)
    }

    /// The song detail's status menu offers a change only when the board and the metadata coordinator
    /// would accept it: `canMutateWorkflowStatus`, not the shorter file-action block (which stays off
    /// during an archive transfer).
    func testSongDetailStatusMenuUsesTheStatusGate() {
        let path = "Sources/FeatureArchiveBrowser/SongDetailView.swift"
        let source = SourceTree.read(path, .code)
        guard let menu = source.range(of: "ArchiveWorkflowStatusMenu("),
              let disabled = source.range(of: ".disabled(", range: menu.upperBound..<source.endIndex) else {
            return Self.rule.check(["\(path) has no status menu with a .disabled gate"])
        }
        let gate = SourceTree.balanced(source, from: disabled.upperBound, open: "(", close: ")")
        Self.rule.require(gate.contains("canMutateWorkflowStatus"), "the status menu's gate in \(path) is `\(gate)`, not canMutateWorkflowStatus")
        Self.rule.require(!gate.contains("blocksGenericProjectVaultFileActions"), "the status menu's gate in \(path) uses the file-action block: `\(gate)`")
    }
}
