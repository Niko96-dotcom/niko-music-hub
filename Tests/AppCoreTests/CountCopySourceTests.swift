import Foundation
import XCTest

/// Every count in a string under Sources/ goes through `CountCopy` (NikoMusicCore).
/// A raw `"\(count) songs"` reads "1 songs"; it shipped twice (8e25a80, e29eafd)
/// because each fix covered only the files it touched.
final class CountCopySourceTests: XCTestCase {
    func testNoRawCountBeforeAPluralNounUnderSources() throws {
        var failures: [String] = []
        for file in try Self.swiftFiles() where !file.hasSuffix(Self.ownerPath) {
            let source = SourceLex.strippedCommentsOnly(try SourceTestSupport.read(file))
            failures += Self.violations(in: source).map { "\(file):\($0)" }
        }
        XCTAssertEqual(
            failures,
            [],
            "A count before a fixed plural reads \"1 songs\". Use CountCopy.count(n, \"song\") or "
                + "CountCopy.noun(for: n, \"song\") from \(Self.ownerPath) instead:\n"
                + failures.joined(separator: "\n")
        )
    }

    /// The detector must catch the shipped mistakes, or it guards nothing.
    func testDetectorCatchesTheShippedMistakes() {
        let shipped = [
            #"var accessibilityLabel: String { "\(title) column, \(songs.count) songs" }"#,
            #"infoLine(label: "Project files", value: "\(liveSong.visibleProjectVersions.count) versions")"#,
            #"help: "\(stage.count) songs in \(stage.status.displayTitle)""#,
            #"return "\(songCount) songs · \(warningPart)""#,
            #"let noun = count == 1 ? "archive folder" : "archive folders""#,
            #"parts.append("\(versions) version\(versions == 1 ? "" : "s")")"#,
        ]
        for line in shipped {
            XCTAssertFalse(Self.violations(in: line).isEmpty, "Detector misses: \(line)")
        }
        let allowed = [
            #"Text("\(name) is ready")"#,
            #""too_short_song=\(title) count=\(clipCount) clips=\(clips)""#,
            #""\(CountCopy.count(n, "song")) in Done""#,
            #"minutes == 0 ? "Unlimited" : CountCopy.count(minutes, "minute")"#,
            #"names.count == 1 ? "Repaired “\(names[0])”." : "Repaired \(CountCopy.count(names.count, "song"))."#,
            #"decodedChannelCount == 1 ? .mono : .preserveMonoStereo"#,
        ]
        for line in allowed {
            XCTAssertEqual(Self.violations(in: line), [], "Detector flags allowed copy: \(line)")
        }
    }

    // MARK: - Detector

    static let ownerPath = "Sources/NikoMusicCore/Domain/CountCopy.swift"

    /// Words after an interpolation that end in "s" but are not plural nouns.
    private static let notPlural: Set<String> = [
        "across", "alias", "always", "as", "does", "focus", "has", "his", "is", "its",
        "minus", "plus", "status", "this", "thus", "was", "yes",
    ]

    /// `\(expr) words` with up to two levels of nested parentheses in `expr`.
    private static let interpolationThenWord = try! NSRegularExpression(
        pattern: #"\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\) ([a-z]+)\b(?!=)"#
    )

    /// A ternary on one that picks between two plain word literals:
    /// `n == 1 ? "song" : "songs"`, `version\(n == 1 ? "" : "s")`.
    private static let handRolledNounChoice = try! NSRegularExpression(
        pattern: #"(?:==|!=|>)\s*1\s*\?\s*"[^"\\]*"\s*:\s*"[^"\\]*""#
    )

    static func violations(in source: String) -> [String] {
        var hits: [String] = []
        let ns = source as NSString
        func line(of location: Int) -> Int {
            ns.substring(to: location).components(separatedBy: "\n").count
        }
        for match in interpolationThenWord.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: match.range(at: 1))
            guard word.hasSuffix("s"), !word.hasSuffix("ss"), !notPlural.contains(word) else { continue }
            hits.append("\(line(of: match.range.location)): \(ns.substring(with: match.range))")
        }
        for match in handRolledNounChoice.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            hits.append("\(line(of: match.range.location)): \(ns.substring(with: match.range))")
        }
        return hits
    }

    private static func swiftFiles() throws -> [String] {
        let root = SourceTestSupport.packageRoot
        let sources = root.appendingPathComponent("Sources")
        guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            return []
        }
        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { String($0.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1)) }
            .sorted()
        XCTAssertGreaterThan(files.count, 100, "Sources/ walk found too few files")
        return files
    }
}
