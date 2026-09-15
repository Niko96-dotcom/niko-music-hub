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
}
