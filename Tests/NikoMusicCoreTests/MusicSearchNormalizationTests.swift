import Foundation
import XCTest
@testable import NikoMusicCore

final class MusicSearchNormalizationTests: XCTestCase {
    func testNormalizationMatchesUnicodeReference() {
        func reference(_ value: String) -> String {
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased().filter { $0.isLetter || $0.isNumber }
        }
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
                      "a\u{0301}b", "ábc", "a\u{200D}b", "🙂ab", "Glühwurm", "blmchn",
                      "123", "1️⃣", "한글", "한", "Mix WAV", "mxwv", "a-b-c"]
        for needle in values {
            for haystack in values {
                XCTAssertEqual(MusicSearchMatcher.isSubsequence(needle, in: haystack),
                               reference(needle, haystack), "\(needle) in \(haystack)")
            }
        }
    }

}
