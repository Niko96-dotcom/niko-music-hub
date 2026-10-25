import XCTest

/// The helper every rule test stands on: the walk finds the tree, matches carry true line numbers, and
/// every failure has the one shape CONTRIBUTING.md describes.
final class SourceTreeTests: XCTestCase {
    func testTheWalkFindsSourcesTestsAndModules() {
        XCTAssertGreaterThan(SourceTree.swiftFiles(under: "Sources/").count, 300)
        XCTAssertTrue(SourceTree.swiftFiles.contains("Tests/RepoRuleTests/SourceTree.swift"))
        XCTAssertTrue(SourceTree.modules.contains("AppCore"))
        XCTAssertTrue(SourceTree.modules.contains("FeatureArchiveBrowser"))
    }

    func testMatchesCarryTheirLineAndCodeViewsKeepLines() {
        let text = "let a = 1\n// Task {\nlet b = \"Task {\"\nTask { }\n"
        XCTAssertEqual(SourceTree.matches(SourceTree.regex(#"Task \{"#), in: SourceLex.stripped(text), path: "f.swift"),
                       [SourceTree.Match(path: "f.swift", line: 4, text: "Task {")])
        XCTAssertEqual(SourceTree.matches(SourceTree.regex(#"Task \{"#), in: SourceLex.strippedCommentsOnly(text)).map(\.line), [3, 4])
    }

    func testFragmentProblemsNameTheFileAndLine() {
        let problems = RepoRule.problems(in: "one\ntwo banned\n", path: "f.swift", contains: ["one", "three"], lacks: ["banned"], because: "a reason")
        XCTAssertEqual(problems, ["f.swift no longer contains `three` (a reason)", "f.swift:2 contains `banned` (a reason)"])
    }

    func testEveryFailureHasTheOneShape() {
        let rule = RepoRule(name: "Count copy", why: "It reads 1 songs", see: "AGENTS.md row \"Count copy\"", fix: "Use CountCopy.count.")
        XCTAssertEqual(
            rule.message("Sources/A.swift:3: `\\(n) songs` counts without CountCopy"),
            "Rule: Count copy. Sources/A.swift:3: `\\(n) songs` counts without CountCopy. Why: It reads 1 songs. "
                + "See: AGENTS.md row \"Count copy\". Fix: Use CountCopy.count."
        )
    }
}
