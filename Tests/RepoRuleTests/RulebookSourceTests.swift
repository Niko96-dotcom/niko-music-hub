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
        let methods = Self.testMethodsByClass()
        var named = 0
        for row in table {
            var currentClass: String?
            // `ClassTests` (n), `ClassTests.testMethod`, and `.testMethod` for the class named just before.
            for match in SourceTree.matches(SourceTree.regex(#"`(\w+Tests)?(?:\.(test\w+))?`(?: \((\d+)\))?"#), in: row) {
                let parts = match.text.split(separator: "`", omittingEmptySubsequences: false)
                let name = parts[1].split(separator: ".", omittingEmptySubsequences: false)
                if !name[0].isEmpty { currentClass = String(name[0]) }
                guard let className = currentClass else { continue }
                named += 1
                guard let defined = methods[className] else {
                    Self.rule.check(["AGENTS.md names \(className), which no test target defines"])
                    continue
                }
                if name.count == 2 {
                    Self.rule.require(defined.contains(String(name[1])), "AGENTS.md names \(className).\(name[1]), which \(className) does not define")
                }
                if let count = Int(parts[2].trimmingCharacters(in: CharacterSet(charactersIn: " ()"))) {
                    Self.rule.require(defined.count == count, "AGENTS.md says \(className) has \(count) tests; it has \(defined.count)")
                }
            }
        }
        XCTAssertGreaterThan(named, 30, "the rules table names too few tests")
    }

    /// Each XCTestCase subclass under Tests/ and the `test…` methods declared after it in its file.
    private static func testMethodsByClass() -> [String: Set<String>] {
        let declaration = SourceTree.regex(#"class (\w+): XCTestCase|func (test\w+)\("#)
        var methods: [String: Set<String>] = [:]
        for file in SourceTree.swiftFiles(under: "Tests/") {
            let text = SourceTree.read(file, .code) as NSString
            var current: String?
            for match in declaration.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                if match.range(at: 1).location != NSNotFound {
                    current = text.substring(with: match.range(at: 1))
                    methods[current!, default: []] = methods[current!, default: []]
                } else if let current {
                    methods[current, default: []].insert(text.substring(with: match.range(at: 2)))
                }
            }
        }
        return methods
    }
}
