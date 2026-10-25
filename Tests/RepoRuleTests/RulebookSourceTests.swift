import XCTest

/// Every test the AGENTS.md rules table names as an enforcer exists, method included, so a renamed or
/// deleted test cannot leave a rule that only looks enforced. The buyer source export leaves AGENTS.md
/// out (script/verify-source-distribution.py), so there the test skips.
/// AGENTS.md "Rules and what enforces them"; CONTRIBUTING.md § Rule tests.
final class RulebookSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Rulebook names real enforcers",
        why: "A row that names a test which no longer exists reads as enforced while nothing checks it",
        see: "AGENTS.md \"Rules and what enforces them\"; CONTRIBUTING.md § Rule tests",
        fix: "Update the row to the test's new name, or move the rule to judgment until a test checks it"
    )

    func testEveryEnforcerNamedInAGENTSExists() throws {
        guard FileManager.default.fileExists(atPath: SourceTree.root.appendingPathComponent("AGENTS.md").path) else {
            throw XCTSkip("AGENTS.md is not in this tree (buyer source export)")
        }
        let table = SourceTree.read("AGENTS.md").components(separatedBy: "\n").filter { $0.hasPrefix("| **") }
        XCTAssertGreaterThan(table.count, 20, "the rules table was not found in AGENTS.md")
        let testFiles = SourceTree.swiftFiles(under: "Tests/")
        let classes = Set(SourceTree.matches(#"class \w+: XCTestCase"#, in: testFiles, .raw).map { $0.text.dropFirst(6).dropLast(12) }.map(String.init))
        let methods = Set(SourceTree.matches(#"func test\w+\("#, in: testFiles, .raw).map { String($0.text.dropFirst(5).dropLast()) })
        var named = 0
        for row in table {
            var currentClass: String?
            // `ClassTests`, `ClassTests.testMethod`, and `.testMethod` for the class named just before.
            for token in SourceTree.matches(SourceTree.regex(#"`(\w+Tests)?(?:\.(test\w+))?`"#), in: row).map(\.text) {
                let parts = token.trimmingCharacters(in: CharacterSet(charactersIn: "`")).split(separator: ".", omittingEmptySubsequences: false)
                if let name = parts.first, !name.isEmpty { currentClass = String(name) }
                guard let className = currentClass else { continue }
                named += 1
                Self.rule.require(classes.contains(className), "AGENTS.md names \(className), which no test target defines")
                if parts.count == 2 {
                    Self.rule.require(methods.contains(String(parts[1])), "AGENTS.md names \(className).\(parts[1]), which does not exist")
                }
            }
        }
        XCTAssertGreaterThan(named, 30, "the rules table names too few tests")
    }
}
