import XCTest
@testable import NikoMusicCore

final class MusicSearchExplainabilityTests: XCTestCase {
    func testTitleMatchSummaryNamesTitleField() throws {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Neon Hook"),
            originalFolderName: "Neon Hook",
            displayTitle: "Neon Hook"
        )
        let index = MusicSearchIndex(songs: [song])

        let result = try XCTUnwrap(index.searchResults("neon").first)
        XCTAssertEqual(result.song.displayTitle, "Neon Hook")
        XCTAssertTrue(result.matchSummary.contains("title"))
    }

    func testFilenameOnlyMatchSummaryNamesPreviewFile() throws {
        let previewOnly = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/Other/Mixdown/alpha prime mix.wav"),
            fileName: "alpha prime mix.wav",
            folderRole: .mixdown,
            modifiedAt: .distantPast,
            detectedRole: .mainMix
        )
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Other"),
            originalFolderName: "Other",
            displayTitle: "Other",
            previewCandidates: [previewOnly]
        )
        let index = MusicSearchIndex(songs: [song])

        let result = try XCTUnwrap(index.searchResults("alpha").first)
        XCTAssertTrue(result.matchSummary.contains("preview"))
    }

    func testMultiTokenSummaryListsEachToken() throws {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Neon Hook"),
            originalFolderName: "Neon Hook",
            displayTitle: "Neon Hook"
        )
        let index = MusicSearchIndex(songs: [song])

        let result = try XCTUnwrap(index.searchResults("neon hk").first)
        XCTAssertTrue(result.matchSummary.contains("neon"))
        XCTAssertTrue(result.matchSummary.contains("hk"))
    }
}
