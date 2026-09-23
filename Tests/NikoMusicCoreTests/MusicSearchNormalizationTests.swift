import Foundation
import XCTest
@testable import NikoMusicCore

final class MusicSearchNormalizationTests: XCTestCase {
    func testNormalizationMatchesUnicodeReference() {
        // Deliberately stable: en_US_POSIX folding plus plain .lowercased()
        // keeps ASCII I/i parity under a Turkish host, while preserving
        // embedded controls (plain lowercasing does not truncate at NUL).
        let stableLocale = Locale(identifier: "en_US_POSIX")
        func reference(_ value: String) -> String {
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: stableLocale)
                .lowercased().filter { $0.isLetter || $0.isNumber }
        }
        // Hardcoded behavior guards independent of the reference helper:
        // ASCII I/i parity, control stripping without truncation, diacritics.
        XCTAssertEqual(MusicSearchMatcher.normalize("I"), "i")
        XCTAssertEqual(MusicSearchMatcher.normalize("i"), "i")
        XCTAssertEqual(MusicSearchMatcher.normalize("NEON MIX"), "neonmix")
        XCTAssertEqual(MusicSearchMatcher.normalize("\r\n\t\0 A1"), "a1")
        XCTAssertEqual(MusicSearchMatcher.normalize("A\0Z9\r\n"), "az9")
        XCTAssertEqual(MusicSearchMatcher.normalize("Glühwurm"), "gluhwurm")
        XCTAssertEqual(MusicSearchMatcher.normalize("Café"), "cafe")
        let corpus = ["", "NEON Hook_v3-MIX.wav", "Glühwurm", "İ I ı i", "Straße", "Σ σ ς",
                      "한글 데모 １２３", "中文音乐", "مرحبا ١٢٣", "cafe\u{301}", "a\u{200D}b",
                      "𝒜①²", "👩🏽‍🎤", "\r\n\t\0 A1", "A\u{FE0F}", "1️⃣", "\u{0301}A"]
        for text in corpus {
            XCTAssertEqual(MusicSearchMatcher.normalize(text), reference(text), text)
        }
        // Every ASCII value, including controls and CRLF grapheme boundaries.
        let ascii = String(String.UnicodeScalarView((0..<128).compactMap(UnicodeScalar.init)))
        XCTAssertEqual(MusicSearchMatcher.normalize(ascii), reference(ascii))
        for value in 0..<128 {
            let text = "A\(UnicodeScalar(value)!)Z9\r\n"
            XCTAssertEqual(MusicSearchMatcher.normalize(text), reference(text))
        }
        // Deterministic mixed Unicode samples exercise the unchanged fallback as well
        // as characters that become ASCII only after locale/diacritic folding.
        for base in stride(from: 0, to: 0x110000, by: 997) {
            let scalars = (base..<min(base + 12, 0x110000)).compactMap(UnicodeScalar.init)
            let text = "Mix_" + String(String.UnicodeScalarView(scalars)) + "_V3"
            XCTAssertEqual(MusicSearchMatcher.normalize(text), reference(text))
        }
    }
    func testTurkishLettersUseStableMappingNotTurkishHostMapping() {
        // ASCII I stays "i" even though an explicit Turkish folding exposes
        // the dotless-"ı" host risk; the "İ I ı i" corpus entry therefore
        // intentionally differs from a Turkish-host mapping.
        XCTAssertEqual(MusicSearchMatcher.normalize("I"), "i")
        let turkishFolded = "I".folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "tr_TR")
        )
        XCTAssertTrue(turkishFolded.contains("ı"), "expected tr_TR to expose dotless-I risk, got: \(turkishFolded)")
        let stable = MusicSearchMatcher.normalize("İ I ı i")
        let turkishMapped = "İ I ı i".folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "tr_TR")
        ).lowercased().filter { $0.isLetter || $0.isNumber }
        XCTAssertNotEqual(stable, turkishMapped, "stable POSIX mapping must differ from tr_TR for Turkish I corpus")
    }
    func testSubsequenceMatchesCharacterReferenceIncludingGraphemeBoundaries() {
        func reference(_ needle: String, _ haystack: String) -> Bool {
            var remaining = haystack[...]
            for character in needle {
                guard let match = remaining.firstIndex(of: character) else { return false }
                remaining = remaining[remaining.index(after: match)...]
            }
            return true
        }
        let values = ["", "ab", "abc", "axbyc", "a\r\nb", "a\0b", "\r\n", "\rX\n",
                      "a\u{0301}b", "ábc", "a\u{200D}b", "🙂ab", "Glühwurm", "glhwrm",
                      "123", "1️⃣", "한글", "한", "Mix WAV", "mxwv", "a-b-c"]
        for needle in values {
            for haystack in values {
                XCTAssertEqual(MusicSearchMatcher.isSubsequence(needle, in: haystack),
                               reference(needle, haystack), "\(needle) in \(haystack)")
            }
        }
    }

}
