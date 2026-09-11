import XCTest
@testable import NikoMusicCore

final class MusicSearchConjunctionTests: XCTestCase {
    func testConjunctionPreservesEveryDetailAndRequiresEveryToken() {
        let folder = URL(fileURLWithPath: "/fixture-only/Original Session")
        let song = Song(
            folderPath: folder, originalFolderName: "Original Session", displayTitle: "Old Title",
            projectVersions: [ProjectVersion(filePath: folder.appendingPathComponent("Arrangement v3.cpr"),
                fileName: "Arrangement v3.cpr", modifiedAt: .distantPast)],
            previewCandidates: [PreviewCandidate(filePath: folder.appendingPathComponent("Bounce mix.wav"),
                fileName: "Bounce mix.wav", folderRole: .mixdown, modifiedAt: .distantPast, detectedRole: .mainMix)],
            scanWarnings: ["Missing reference"], sidecarNotes: "Alternate chorus",
            virtualTitle: "  Glühwurm Neon  ", aliases: ["Summer Demo"], appNote: "Approval pending",
            collaboratorNames: ["María Klein"], workflowStatus: .waitingFeedback
        )
        // Include hits in every field, fuzzy hits, duplicate tokens, and misses in either position.
        let tokens = ["gluhwurm", "neon", "glhwrm", "summer", "smmer", "maria", "mrkl",
                      "waiting", "original", "orgnl", "arrangement", "arrngmnt", "bounce",
                      "bncmx", "missing", "mssng", "approval", "apprvl", "chorus", "chrs", "zzzz"]
        let singles = tokens.map { MusicSearchMatcher.matchDetails(song: song, queryTokens: [$0]) }
        for first in tokens.indices {
            for second in tokens.indices {
                let expected = singles[first].isEmpty || singles[second].isEmpty
                    ? [] : singles[first] + singles[second]
                XCTAssertEqual(MusicSearchMatcher.matchDetails(song: song,
                    queryTokens: [tokens[first], tokens[second]]), expected)
            }
        }
        XCTAssertEqual(MusicSearchMatcher.matchDetails(song: song, queryTokens: []), [])
        XCTAssertEqual(MusicSearchMatcher.matchDetails(song: song, queryTokens: ["neon", "zzzz", "maria"]), [])
        XCTAssertEqual(MusicSearchMatcher.matchDetails(song: song, queryTokens: ["neon", "maria", "zzzz"]), [])
        XCTAssertEqual(MusicSearchMatcher.matchDetails(song: song, queryTokens: ["", "neon"]), [])
    }
    func testRepeatedQueriesUseMetadataFromTheLatestRebuild() {
        var song = Song(folderPath: URL(fileURLWithPath: "/fixture-only/Seed"),
                        originalFolderName: "Seed", displayTitle: "Seed", virtualTitle: "Glühwurm")
        var index = MusicSearchIndex(songs: [song])
        XCTAssertEqual(index.search("gluhwurm").map(\.id), [song.id])
        song.virtualTitle = "Ocean"
        index.rebuild(from: [song])
        XCTAssertTrue(index.search("gluhwurm").isEmpty)
        XCTAssertEqual(index.search("ocean").map(\.id), [song.id])
    }

}
