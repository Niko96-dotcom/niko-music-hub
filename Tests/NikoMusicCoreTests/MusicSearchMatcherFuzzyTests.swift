import XCTest
@testable import NikoMusicCore

final class MusicSearchMatcherFuzzyTests: XCTestCase {
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
        XCTAssertFalse(details.isEmpty)
    }
}
