import Foundation
import XCTest

/// The repository as a rule test reads it. Files are read once per test run; Swift files are listed
/// by path, so a test asks for a module with a prefix ("Sources/FeatureArchiveBrowser/").
enum SourceTree {
    /// How a rule reads a file. `code` blanks comments and string literals, so prose or a
    /// commented-out call cannot fake a pass; `codeAndStrings` blanks only comments, for rules about
    /// literals. Both keep every newline, so line numbers stay true (`SourceLex`).
    enum View: String, Sendable {
        case raw, code, codeAndStrings
    }

    /// One match of a pattern, with the line it starts on.
    struct Match: CustomStringConvertible, Equatable, Sendable {
        let path: String
        let line: Int
        let text: String

        var description: String { path.isEmpty ? "line \(line): `\(text)`" : "\(path):\(line): `\(text)`" }
    }

    /// The package root: this file is `Tests/RepoRuleTests/SourceTree.swift`.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every Swift file under `Sources/` and `Tests/`, relative to the root, sorted.
    static let swiftFiles: [String] = ["Sources", "Tests"].flatMap { directory -> [String] in
        let base = root.standardizedFileURL.path + "/"
        let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)
        return (enumerator?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }
            .map { String($0.standardizedFileURL.path.dropFirst(base.count)) }
    }.sorted()

    /// The module directories under `Sources/`.
    static let modules: [String] = Set(swiftFiles.compactMap { path -> String? in
        let parts = path.split(separator: "/")
        return parts.count > 2 && parts[0] == "Sources" ? String(parts[1]) : nil
    }).sorted()

    /// The Swift files whose path starts with `prefix`; fails the test when the walk finds fewer
    /// than `minimum`, so a moved folder cannot turn a rule into a check of nothing.
    static func swiftFiles(under prefix: String, atLeast minimum: Int = 1, file: StaticString = #filePath, line: UInt = #line) -> [String] {
        let files = swiftFiles.filter { $0.hasPrefix(prefix) }
        if files.count < minimum {
            XCTFail("The walk of \(prefix) found \(files.count) Swift files, expected at least \(minimum)", file: file, line: line)
        }
        return files
    }

    /// A file's text as `view` shows it. A missing file fails the test and reads as empty.
    static func read(_ path: String, _ view: View = .raw, file: StaticString = #filePath, line: UInt = #line) -> String {
        if let cached = cache.value(for: "\(view.rawValue):\(path)") { return cached }
        let text: String
        switch view {
        case .raw:
            guard let contents = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
                XCTFail("A rule reads \(path), and it is missing. Update the rule test with the file's new path.", file: file, line: line)
                return ""
            }
            text = contents
        case .code: text = SourceLex.stripped(read(path, file: file, line: line))
        case .codeAndStrings: text = SourceLex.strippedCommentsOnly(read(path, file: file, line: line))
        }
        cache.store(text, for: "\(view.rawValue):\(path)")
        return text
    }

    /// Every match of `pattern` in each file of `paths`, read as `view`.
    static func matches(_ pattern: String, in paths: [String], _ view: View = .code) -> [Match] {
        let regex = regex(pattern)
        return paths.flatMap { matches(regex, in: read($0, view), path: $0) }
    }

    /// Every match of `regex` in `text` (a planted line in a detector's self-test, or a file's text).
    static func matches(_ regex: NSRegularExpression, in text: String, path: String = "") -> [Match] {
        let ns = text as NSString
        let found = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !found.isEmpty else { return [] }
        let newlines = newlineOffsets(in: text)
        return found.map { match in
            Match(path: path, line: line(of: match.range.location, newlines: newlines), text: ns.substring(with: match.range))
        }
    }

    /// The 1-based line of a UTF-16 offset.
    static func lineNumber(of location: Int, in text: NSString) -> Int {
        line(of: location, newlines: newlineOffsets(in: text as String))
    }

    private static func newlineOffsets(in text: String) -> [Int] {
        text.utf16.enumerated().compactMap { $0.element == 10 ? $0.offset : nil }
    }

    /// One more than the number of newlines before `location` (binary search).
    private static func line(of location: Int, newlines: [Int]) -> Int {
        var low = 0, high = newlines.count
        while low < high {
            let middle = (low + high) / 2
            if newlines[middle] < location { low = middle + 1 } else { high = middle }
        }
        return low + 1
    }

    /// A pattern every rule test writes literally; an invalid one is a bug in the test.
    static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        do { return try NSRegularExpression(pattern: pattern, options: options) } catch { fatalError("Invalid rule pattern \(pattern): \(error)") }
    }

    /// The text from just after an opening bracket at `start` to its matching closing bracket.
    static func balanced(_ text: String, from start: String.Index, open: Character, close: Character) -> String {
        var depth = 1
        var index = start
        while index < text.endIndex {
            if text[index] == open { depth += 1 }
            if text[index] == close {
                depth -= 1
                if depth == 0 { return String(text[start..<index]) }
            }
            index = text.index(after: index)
        }
        return String(text[start...])
    }

    private static let cache = TextCache()
}

/// A repository rule and the one failure shape every rule test uses:
/// `Rule: <name>. <what is wrong, at file:line>. Why: <why>. See: <AGENTS.md row and doc>. Fix: <fix>.`
struct RepoRule: Sendable {
    let name: String
    let why: String
    let see: String
    let fix: String

    func message(_ problem: String) -> String {
        "Rule: \(name). \(Self.sentence(problem)) Why: \(Self.sentence(why)) See: \(Self.sentence(see)) Fix: \(Self.sentence(fix))"
    }

    /// One failure per problem.
    func check(_ problems: [String], file: StaticString = #filePath, line: UInt = #line) {
        for problem in problems { XCTFail(message(problem), file: file, line: line) }
    }

    func check(_ matches: [SourceTree.Match], _ wrong: String, file: StaticString = #filePath, line: UInt = #line) {
        check(matches.map { "\($0) \(wrong)" }, file: file, line: line)
    }

    func require(_ condition: Bool, _ problem: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        if !condition { XCTFail(message(problem()), file: file, line: line) }
    }

    /// `path`, read as `view`, contains every fragment of `contains` and none of `lacks`.
    func expect(_ path: String, _ view: SourceTree.View = .raw, contains: [String] = [], lacks: [String] = [],
                because note: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let text = SourceTree.read(path, view, file: file, line: line)
        check(Self.problems(in: text, path: path, contains: contains, lacks: lacks, because: note), file: file, line: line)
    }

    /// What `expect(_:contains:lacks:)` reports: each missing fragment, and each present one at its line.
    static func problems(in text: String, path: String, contains: [String], lacks: [String], because note: String?) -> [String] {
        let reason = note.map { " (\($0))" } ?? ""
        var problems = contains.filter { !text.contains($0) }.map { "\(path) no longer contains `\($0)`\(reason)" }
        for fragment in lacks {
            if let range = text.range(of: fragment) {
                let at = SourceTree.lineNumber(of: NSRange(range, in: text).location, in: text as NSString)
                problems.append("\(path):\(at) contains `\(fragment)`\(reason)")
            }
        }
        return problems
    }

    /// `path`, read as `view` (code by default), has a match for `pattern`; `what` names it.
    func expect(_ path: String, _ view: SourceTree.View = .code, matching pattern: String, _ what: String,
                file: StaticString = #filePath, line: UInt = #line) {
        let found = SourceTree.read(path, view, file: file, line: line).range(of: pattern, options: .regularExpression) != nil
        require(found, "\(path) no longer shows \(what)", file: file, line: line)
    }

    /// `path`, read as `view` (code by default), has no match for `pattern`; `what` names it.
    func expect(_ path: String, _ view: SourceTree.View = .code, notMatching pattern: String, _ what: String,
                file: StaticString = #filePath, line: UInt = #line) {
        check(SourceTree.matches(pattern, in: [path], view), what, file: file, line: line)
    }

    private static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix(".") || trimmed.hasSuffix("?") ? trimmed : trimmed + "."
    }
}

/// The texts read so far. A test run reads each file once; XCTest may call from more than one thread.
private final class TextCache: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String: String] = [:]

    func value(for key: String) -> String? {
        lock.withLock { texts[key] }
    }

    func store(_ text: String, for key: String) {
        lock.withLock { texts[key] = text }
    }
}
