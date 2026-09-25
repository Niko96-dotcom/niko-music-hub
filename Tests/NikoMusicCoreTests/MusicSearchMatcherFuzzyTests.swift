import XCTest
@testable import NikoMusicCore

final class MusicSearchMatcherFuzzyTests: XCTestCase {
    func testTokenCannotSpanUnrelatedMetadataFields() {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/search-fixture"),
            originalFolderName: "Ver",
            displayTitle: "Be",
            aliases: ["Ly"]
        )
        XCTAssertTrue(MusicSearchMatcher.matchDetails(song: song, queryTokens: ["beverly"]).isEmpty)
        XCTAssertFalse(MusicSearchMatcher.matchDetails(song: song, queryTokens: ["be", "ly"]).isEmpty)
    }

    func testBoundedEditDistanceMatchesTypo() {
        XCTAssertEqual(MusicSearchMatcher.boundedEditDistance("neon", "noen", max: 2), 1)
    }

    func testTypoMatchesSongTitle() {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Neon Hook", isDirectory: true),
            originalFolderName: "Neon Hook",
            displayTitle: "Neon Hook"
        )
        let details = MusicSearchMatcher.matchDetails(song: song, queryTokens: ["noen"])
        XCTAssertEqual(details.first?.kind, .fuzzyTitle)
        XCTAssertFalse(MusicSearchMatcher.matchDetails(song: song, queryTokens: ["hooj"]).isEmpty)
    }

    func testBoundedWindowRetainsTightMatchRejectsSpread() {
        XCTAssertTrue(MusicSearchMatcher.isSubsequenceWithinBound("abc", in: "abc"))
        XCTAssertTrue(MusicSearchMatcher.isSubsequenceWithinBound("abc", in: "aXbXc"))
        // Bound is 2*3=6; aXXXbXXXc spans 9 and must be rejected.
        XCTAssertFalse(MusicSearchMatcher.isSubsequenceWithinBound("abc", in: "aXXXbXXXc"))
        // Every bounded hit is a true subsequence.
        XCTAssertTrue(MusicSearchMatcher.isSubsequence("abc", in: "aXXXbXXXc"))
        XCTAssertTrue(MusicSearchMatcher.isSubsequence("abc", in: "aXbXc"))
    }

    func testLaterStartSucceedsAfterEarlyOverBoundFailure() {
        // Needle "az" has bound 4. The first 'a' sees no 'z' in its window,
        // but the second 'a' is immediately followed by 'z'.
        let haystack = "a" + String(repeating: "x", count: 10) + "az"
        XCTAssertTrue(MusicSearchMatcher.isSubsequenceWithinBound("az", in: haystack))
        // Early over-bound distance alone must not match.
        XCTAssertFalse(MusicSearchMatcher.isSubsequenceWithinBound("az", in: "a" + String(repeating: "x", count: 10) + "z"))
    }

    func testLongRepeatedStringsWithTrailingZ() {
        let haystack = String(repeating: "a", count: 5000) + String(repeating: "b", count: 5000) + "z"
        // No 'a'..'b'..'z' fits in bound 6, so false — and the bounded scan stays linear.
        XCTAssertFalse(MusicSearchMatcher.isSubsequenceWithinBound("abz", in: haystack))
        // A tight trailing match still succeeds.
        XCTAssertTrue(MusicSearchMatcher.isSubsequenceWithinBound("abz", in: haystack + "abz"))
    }

    func testBoundedUnicodePath() {
        XCTAssertTrue(MusicSearchMatcher.isSubsequenceWithinBound("éa", in: "éa"))
        XCTAssertFalse(MusicSearchMatcher.isSubsequenceWithinBound("éa", in: "é" + String(repeating: "x", count: 10) + "a"))
        let haystack = "é" + String(repeating: "x", count: 10) + "éa"
        XCTAssertTrue(MusicSearchMatcher.isSubsequenceWithinBound("éa", in: haystack))
    }
}
