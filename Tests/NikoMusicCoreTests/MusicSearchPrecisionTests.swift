import XCTest
@testable import NikoMusicCore

final class MusicSearchPrecisionTests: XCTestCase {
    private func song(
        title: String,
        folder: String? = nil,
        previews: [PreviewCandidate] = []
    ) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: "/tmp/\(folder ?? title)"),
            originalFolderName: folder ?? title,
            displayTitle: title,
            previewCandidates: previews
        )
    }

    private func preview(fileName: String) -> PreviewCandidate {
        PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/preview/\(fileName)"),
            fileName: fileName,
            folderRole: .mixdown,
            modifiedAt: .distantPast,
            detectedRole: .mainMix
        )
    }

    func testAuroraQueryReturnsOnlyTitleMatches() {
        let index = MusicSearchIndex(songs: [
            song(title: "Aurora"),
            song(title: "AURORA - ROME"),
            song(
                title: "OTHER ARTIST - DEMO",
                previews: [preview(fileName: "AURORA - SONG X SESSION BOUNCE (Aurora, Megan).wav")]
            ),
            song(
                title: "Friday Beat",
                previews: [preview(fileName: "06 Crash Transition.wav")]
            ),
        ])

        // The preview-filename substring hit is secondary tier and suppressed.
        XCTAssertEqual(
            index.search("aurora").map(\.displayTitle),
            ["Aurora", "AURORA - ROME"]
        )
        // The thin subsequence spread across the long filename is rejected.
        XCTAssertTrue(index.search("chanin").isEmpty)
    }

    func testSecondaryTierUsedAsFallbackWhenNoPrimaryResult() {
        let index = MusicSearchIndex(songs: [
            song(title: "Alpha"),
            song(title: "Other", previews: [preview(fileName: "zebra mix.wav")]),
        ])

        XCTAssertEqual(index.search("zebra").map(\.displayTitle), ["Other"])
    }

    func testFuzzyStillWorksAsFallback() {
        let index = MusicSearchIndex(songs: [song(title: "Neon Hook")])

        XCTAssertEqual(index.search("neohok").count, 1)
        XCTAssertEqual(index.search("noen").count, 1)
        XCTAssertEqual(index.search("neon hk").count, 1)
    }

    func testStrongMatchSuppressesFuzzyMatch() {
        let index = MusicSearchIndex(songs: [
            song(title: "Neon Hook"),
            song(title: "Noen Days"),
        ])

        // "Neon Hook" matches via title prefix; "Noen Days" only via a
        // one-transposition typo, so tiering keeps just the strong hit.
        XCTAssertEqual(index.search("neon").map(\.displayTitle), ["Neon Hook"])

        // With only the typo title indexed, the fuzzy fallback still finds it.
        let fallback = MusicSearchIndex(songs: [song(title: "Noen Days")])
        XCTAssertEqual(fallback.search("neon").map(\.displayTitle), ["Noen Days"])
    }

    func testMinimalSubsequenceWindowBound() {
        XCTAssertTrue(MusicSearchMatcher.isSubsequenceWithinBound("nly", in: "notesonly"))
        XCTAssertTrue(MusicSearchMatcher.isSubsequenceWithinBound("brkn", in: "brokenfolderexample"))
        XCTAssertTrue(MusicSearchMatcher.isSubsequenceWithinBound("hk", in: "neonhook"))
        XCTAssertFalse(
            MusicSearchMatcher.isSubsequenceWithinBound("chanin", in: "06crashtransitionwav")
        )
    }

    func testFolderHitRemainsPrimaryAlongsideTitleHits() {
        let index = MusicSearchIndex(songs: [
            song(title: "AURORA - ROME"),
            song(title: "Life Slow", folder: "AURORA DAY 3"),
        ])

        XCTAssertEqual(
            Set(index.search("aurora").map(\.displayTitle)),
            Set(["AURORA - ROME", "Life Slow"])
        )
    }

    func testAppNotePrimaryNotShadowedByPreviewFileName() {
        let other = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Other"),
            originalFolderName: "Other",
            displayTitle: "Other",
            previewCandidates: [preview(fileName: "chanin-bounce.wav")],
            appNote: "chanin"
        )
        let index = MusicSearchIndex(songs: [other, song(title: "Chanin")])

        let results = index.searchResults("chanin")
        XCTAssertEqual(
            Set(results.map(\.song.displayTitle)),
            Set(["Other", "Chanin"])
        )
        XCTAssertEqual(
            results.first(where: { $0.song.displayTitle == "Other" })?.details.first?.kind,
            .appNote
        )
    }

    func testFolderPrimaryNotShadowedByFuzzyAlias() {
        let other2 = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Other2"),
            originalFolderName: "Chanin",
            displayTitle: "Other2",
            aliases: ["Chaining"]
        )
        let index = MusicSearchIndex(songs: [other2, song(title: "Chanin")])

        let results = index.searchResults("chanin")
        XCTAssertEqual(
            Set(results.map(\.song.displayTitle)),
            Set(["Other2", "Chanin"])
        )
        XCTAssertEqual(
            results.first(where: { $0.song.displayTitle == "Other2" })?.details.first?.kind,
            .folderName
        )
    }

    func testMultiTokenTierIsWeakestToken() {
        let index = MusicSearchIndex(songs: [
            song(title: "AURORA - ROME", previews: [preview(fileName: "bounce.wav")]),
            song(title: "Aurora Bounce"),
        ])

        // "bounce" hits only the preview filename for ROME (secondary), so the
        // weakest-token tier drops it while the all-title match stays primary.
        XCTAssertEqual(
            index.search("aurora bounce").map(\.displayTitle),
            ["Aurora Bounce"]
        )
    }

    func testSubsequenceBoundEdge() {
        XCTAssertTrue(MusicSearchMatcher.isSubsequenceWithinBound("abc", in: "axbxxc"))
        XCTAssertFalse(MusicSearchMatcher.isSubsequenceWithinBound("abc", in: "axbxxxc"))
    }

    func testNonAsciiFuzzySubsequence() {
        let index = MusicSearchIndex(songs: [song(title: "GLÜHWURM")])

        XCTAssertEqual(index.search("glhwrm").count, 1)
    }

    func testEditDistanceBudgetByTokenLength() {
        let neon = MusicSearchIndex(songs: [song(title: "Neon Hook")])

        // Length 4 allows distance 1 only; "nxxn" is distance 2 from "neon".
        XCTAssertTrue(neon.search("nxxn").isEmpty)

        let hello = MusicSearchIndex(songs: [song(title: "Hello Street")])

        // Length 5 allows distance 2; "hxllx" is distance 2 from "hello".
        XCTAssertEqual(hello.search("hxllx").count, 1)
    }
}
