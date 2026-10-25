import XCTest

/// Every count in a string under Sources/ goes through `CountCopy` (NikoMusicCore). A raw
/// `"\(count) songs"` reads "1 songs"; it shipped twice (8e25a80, e29eafd) because each fix covered only
/// the files it touched. AGENTS.md row "Count copy"; Sources/NikoMusicCore/Domain/CountCopy.swift.
final class CountCopySourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Count copy",
        why: "A count before a fixed plural reads \"1 songs\"; it shipped twice",
        see: "AGENTS.md row \"Count copy\"; \(ownerPath)",
        fix: "Use CountCopy.count(n, \"song\") or CountCopy.noun(for: n, \"song\")"
    )

    static let ownerPath = "Sources/NikoMusicCore/Domain/CountCopy.swift"

    func testNoRawCountBeforeAPluralNounUnderSources() {
        let files = SourceTree.swiftFiles(under: "Sources/", atLeast: 100).filter { $0 != Self.ownerPath }
        Self.rule.check(files.flatMap { Self.violations(in: SourceTree.read($0, .codeAndStrings), path: $0) }, "counts without CountCopy")
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

    /// Words after an interpolation that end in "s" but are not plural nouns.
    private static let notPlural: Set<String> = [
        "across", "alias", "always", "as", "does", "focus", "has", "his", "is", "its",
        "minus", "plus", "status", "this", "thus", "was", "yes",
    ]

    /// `\(expr) words` with up to two levels of nested parentheses in `expr`.
    private static let interpolationThenWord = SourceTree.regex(#"\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\) ([a-z]+)\b(?!=)"#)

    /// A ternary on one that picks between two plain word literals:
    /// `n == 1 ? "song" : "songs"`, `version\(n == 1 ? "" : "s")`.
    private static let handRolledNounChoice = SourceTree.regex(#"(?:==|!=|>)\s*1\s*\?\s*"[^"\\]*"\s*:\s*"[^"\\]*""#)

    static func violations(in source: String, path: String = "") -> [SourceTree.Match] {
        let plurals = SourceTree.matches(interpolationThenWord, in: source, path: path).filter { match in
            let word = String(match.text.split(separator: " ").last ?? "")
            return word.hasSuffix("s") && !word.hasSuffix("ss") && !notPlural.contains(word)
        }
        return plurals + SourceTree.matches(handRolledNounChoice, in: source, path: path)
    }
}
