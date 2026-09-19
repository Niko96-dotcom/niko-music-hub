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
    func testUnrebuiltIndexIsStableAndRebuildInvalidatesNormalizedCache() {
        // Guards a future normalized-field cache: without rebuild nothing changes;
        // with rebuild the new metadata is visible and the old digest is gone.
        // Covers title, alias, collaborator, note and folder paths in one probe.
        var song = Song(folderPath: URL(fileURLWithPath: "/fixture-only/Cache"),
                        originalFolderName: "Cache Folder", displayTitle: "Cache Title",
                        sidecarNotes: "cache notes", aliases: ["Cache Alias"],
                        appNote: "cache approval", collaboratorNames: ["Cache Maria"])
        let index = MusicSearchIndex(songs: [song])
        func signature(_ results: [MusicSearchResult]) -> String {
            results.map { "\($0.song.id)|\($0.score)|\($0.matchSummary)" }.joined(separator: "\n")
        }
        let before = signature(index.searchResults("cache"))
        XCTAssertFalse(before.isEmpty)
        XCTAssertEqual(signature(index.searchResults("cache")), before)
        // Mutating the caller's copy alone must not leak into the index.
        song.virtualTitle = "ZZ Top Unique Invalidation Title"
        song.aliases = ["Unrelated"]
        song.collaboratorNames = ["Unrelated"]
        song.sidecarNotes = "unrelated"
        song.appNote = "unrelated"
        XCTAssertEqual(signature(index.searchResults("cache")), before)
        XCTAssertTrue(index.searchResults("top").isEmpty)
        var rebuilt = index
        rebuilt.rebuild(from: [song])
        // The folder is unchanged: originalFolderName "Cache Folder" still
        // contains "cache", so the rebuilt index must still match via folder
        // (not empty), but with a new score/explanation because the title,
        // alias, collaborator and notes no longer contain "cache".
        let rebuiltCache = rebuilt.searchResults("cache")
        XCTAssertFalse(rebuiltCache.isEmpty)
        XCTAssertEqual(rebuiltCache.map(\.song.id), [song.id])
        XCTAssertTrue(rebuiltCache.first?.matchSummary.contains("folder") == true)
        XCTAssertNotEqual(signature(rebuiltCache), before)
        // Removed metadata/collaborator must no longer match on their own terms.
        XCTAssertTrue(rebuilt.searchResults("maria").isEmpty)
        XCTAssertTrue(rebuilt.searchResults("alias").isEmpty)
        XCTAssertTrue(rebuilt.searchResults("approval").isEmpty)
        XCTAssertEqual(rebuilt.search("top").map(\.id), [song.id])
        XCTAssertNotEqual(signature(rebuilt.searchResults("top")), before)
    }

}
