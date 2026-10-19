import XCTest
@testable import NikoMusicCore

/// `CompiledRegex` replaces `String.range(of:options: .regularExpression)` and
/// `replacingOccurrences(of:with:options: .regularExpression)` on the filename hot paths. These
/// tests pin that it answers exactly what those string APIs answer, over the patterns in use and
/// filenames with separators, dates, tempo tags, accents, emoji and line breaks.
final class CompiledRegexTests: XCTestCase {
    private let patterns: [(pattern: String, caseInsensitive: Bool)] = [
        (#"\s+[-–—]\s*"#, false),
        (#"(?i)\b[0-9a-f]{32}\b"#, false),
        (#"(?i)\b(?:official(?:\s+music)?|lyrics?)\s+video\b"#, false),
        (#"\[\d{4}-\d{2}-\d{2}"#, false),
        (#"(?i)\b\d+\s*bpm\b"#, false),
        (#"^(?:0\d(?:[-_]\d{1,3})?(?:$|[-_%])|\d{1,3}[-_]\d{1,3}(?:$|[-_%])|\d{1,3}_)"#, false),
        (#"(?i)\b(?:no[ _-]+(?:lim(?:iter)?|clip(?:per)?|master)|unlimited|unmastered|premaster|pre[ _-]+master|for[ _-]+(?:mastering|ableton|cubase))\b"#, false),
        (#"(?i)\s+(?:(?:demo|demmo|prod|production|mixdown|mix|master|bounce|preview)\b(?=\s*(?:$|\(|v(?:ersion)?\s*\d))|v(?:ersion)?\s*\d+(?:\.\d+)*\b|premaster\b)|\s+\([^)]*,|\s+(?:instrumental|instr|acapella|vocals?|vox|stems?|reference|ref)(?:\s+v\d+)?$"#, false),
        (#"[\[\(]\s*\d{4}[-_]\d{1,2}[-_]\d{1,2}(\s+\d{1,6}([:\-]\d{2}){0,2})?\s*[\]\)]"#, false),
        (#"(19|20)\d{2}[-_]\d{1,2}[-_]\d{1,2}"#, false),
        (#"(?<![0-9])\d{1,2}[-_]\d{1,2}[-_](\d{4}|\d{2})(?![0-9])"#, false),
        (#"(?i)(?<![0-9])\d{1,3}[\s_-]*bpm(?![a-z])"#, false),
        (#"\bv\d+\b"#, true),
        (#"\bversion\s*\d+\b"#, true),
        (#"\bv0\.\d+\b"#, true),
        (#"\s*[-–—]?\s*[vV]\s*\d+\s*$"#, false),
        (#"\s+\d+\s*$"#, false),
        (#"^v\d+$"#, false),
        (#"^[0-9a-f]{8}[-\s]?[0-9a-f]{4}[-\s]?[0-9a-f]{4}[-\s]?[0-9a-f]{4}[-\s]?[0-9a-f]{12}$"#, false),
    ]

    private let corpus: [String] = [
        "",
        "Song",
        "Song v2 mix",
        "Song V12 FINAL",
        "Track v2 v5 bounce",
        "Artist - Title (Demo)",
        "Artist \u{2013} Title mixdown v3",
        "Artist \u{2014}Title   mastered",
        "Song [2026-09-04 10:11:12] mix",
        "Song (2026_9_4) v2",
        "Song 2026-09-04 mix 3",
        "Song 04-09-2026 take 2",
        "Song 140 BPM",
        "Song 140bpm final",
        "Song 140 bpmx",
        "d3b07384d113edec49eaa6238ad5ff00 mix",
        "123e4567-e89b-12d3-a456-426614174000",
        "123e4567 e89b 12d3 a456 426614174000",
        "01-01%20Imported name",
        "99 Red Stars",
        "404",
        "Track_01_02 - Lead Vox",
        "Song (feat. X, Y) v2",
        "Song (Bass)",
        "Song instrumental v2",
        "Song unmastered for mastering",
        "Song no limiter",
        "Song pre master",
        "Official Music Video",
        "lyrics video final",
        "emoji \u{1F3B5} v2 mix",
        "Caf\u{00E9} \u{00FC}ber v3 \u{2013} Mix",
        "decomposed cafe\u{0301} v4",
        "\u{FF21}\u{FF22}\u{FF23} v\u{FF11}\u{FF12}",
        "line\nbreak v3",
        "tab\tseparated v7",
        "v0.6 demo",
        "Song v1.2.3",
        "Song 12",
        "  leading and trailing  ",
        "Song - ",
        "- Song",
    ]

    func testSearchMatchesTheStringRegularExpressionAPI() {
        for (pattern, caseInsensitive) in patterns {
            let compiled = CompiledRegex(pattern, caseInsensitive: caseInsensitive)
            let options: String.CompareOptions = caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression
            for text in corpus {
                let expected = text.range(of: pattern, options: options)
                XCTAssertEqual(compiled.firstMatchRange(in: text), expected, "range \(pattern) in \(text.debugDescription)")
                XCTAssertEqual(compiled.hasMatch(in: text), expected != nil, "hasMatch \(pattern) in \(text.debugDescription)")
            }
        }
    }

    func testReplacementMatchesTheStringRegularExpressionAPI() {
        for (pattern, caseInsensitive) in patterns {
            let compiled = CompiledRegex(pattern, caseInsensitive: caseInsensitive)
            let options: String.CompareOptions = caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression
            for text in corpus {
                for template in [" ", ""] {
                    XCTAssertEqual(
                        compiled.replacingMatches(in: text, with: template),
                        text.replacingOccurrences(of: pattern, with: template, options: options),
                        "replace \(pattern) in \(text.debugDescription) with \(template.debugDescription)"
                    )
                }
            }
        }
    }

    func testMatchesReturnsEveryMatchWithItsCaptureGroup() {
        let compiled = CompiledRegex(#"(?i)(?:^|[\s_-])v(?:ersion)?\s*(\d+)(?:\.\d+)*(?=$|[\s_()\[\]-])"#)
        let text = "Track v2 v5 bounce"
        let captured = compiled.matches(in: text).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
        XCTAssertEqual(captured, ["2", "5"])
    }
}
