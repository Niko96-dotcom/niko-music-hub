import XCTest

/// Archive views state intent; `ArchivePageModel` owns the page. Views that wrote `viewMode` themselves
/// drifted from the model's own rules before (477f9ae fixed four view copies of `showsBoardPage`). The
/// compiler keeps the page in `ArchivePageModel.swift`: both setters are `private(set)`, so a write from a
/// view, the view model or another owner does not compile. This test keeps the setters private.
/// AGENTS.md row "Archive page"; docs/architecture.md § Archive page state.
final class ArchiveViewIntentSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Archive page",
        why: "Views that wrote the page themselves drifted from the page model's rules",
        see: "AGENTS.md row \"Archive page\"; docs/architecture.md § Archive page state",
        fix: "Call an intent (openSongDetail, showBoard, setBrowseLayout(list:), showAnalytics, clearSelection, …); keep the setters private(set)"
    )

    func testThePageSettersStayPrivate() {
        let page = "Sources/FeatureArchiveBrowser/ArchivePageModel.swift"
        Self.rule.expect(page, matching: #"@Published\s+private\(set\)\s+var\s+viewMode\b"#, "`viewMode` with a private(set) setter")
        Self.rule.expect(page, matching: #"@Published\s+private\(set\)\s+var\s+listShowsDetail\b"#, "`listShowsDetail` with a private(set) setter")
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
