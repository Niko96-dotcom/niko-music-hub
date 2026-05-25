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

    func testSidecarNotesMatchSummaryNamesSongNoteField() throws {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Broken"),
            originalFolderName: "Broken",
            displayTitle: "Broken",
            sidecarNotes: "notes only"
        )
        let index = MusicSearchIndex(songs: [song])

        let result = try XCTUnwrap(index.searchResults("only").first)
        XCTAssertTrue(result.matchSummary.contains("song note"))
    }

    func testFuzzyFolderNameMatchSummaryNamesFuzzyFolderField() throws {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Broken Folder Example"),
            originalFolderName: "Broken Folder Example",
            displayTitle: "Renamed Later"
        )
        let index = MusicSearchIndex(songs: [song])

        let result = try XCTUnwrap(index.searchResults("brkn fld").first)
        XCTAssertEqual(result.song.displayTitle, "Renamed Later")
        XCTAssertTrue(result.matchSummary.contains("fuzzy folder"))
        XCTAssertFalse(result.matchSummary.contains("fuzzy text"))
    }

    func testFuzzySidecarNotesMatchSummaryNamesFuzzySongNoteField() throws {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Broken"),
            originalFolderName: "Broken",
            displayTitle: "Broken",
            sidecarNotes: "notes only"
        )
        let index = MusicSearchIndex(songs: [song])

        let result = try XCTUnwrap(index.searchResults("nts nly").first)
        XCTAssertEqual(result.song.displayTitle, "Broken")
        XCTAssertTrue(result.matchSummary.contains("fuzzy song note"))
        XCTAssertFalse(result.matchSummary.contains("fuzzy text"))
    }

    func testScanWarningMatchSummaryNamesScanWarningField() throws {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Broken"),
            originalFolderName: "Broken",
            displayTitle: "Broken",
            scanWarnings: ["No CPR project files found"]
        )
        let index = MusicSearchIndex(songs: [song])

        let result = try XCTUnwrap(index.searchResults("project").first)
        XCTAssertTrue(result.matchSummary.contains("scan warning"))
    }

    func testFuzzyCPRFileNameMatchSummaryNamesFuzzyCPRField() throws {
        let version = ProjectVersion(
            filePath: URL(fileURLWithPath: "/tmp/Unrelated/Secret Project Alpha.cpr"),
            fileName: "Secret Project Alpha.cpr",
            modifiedAt: .distantPast
        )
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Unrelated"),
            originalFolderName: "Unrelated",
            displayTitle: "Unrelated",
            projectVersions: [version]
        )
        let index = MusicSearchIndex(songs: [song])

        let result = try XCTUnwrap(index.searchResults("scrt prj").first)
        XCTAssertTrue(result.matchSummary.contains("fuzzy CPR file"))
        XCTAssertFalse(result.matchSummary.contains("fuzzy text"))
    }

    func testFuzzyPreviewFileNameMatchSummaryNamesFuzzyPreviewField() throws {
        let preview = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/Unrelated/Mixdown/Lab Song v3 mix.wav"),
            fileName: "Lab Song v3 mix.wav",
            folderRole: .mixdown,
            modifiedAt: .distantPast,
            detectedRole: .mainMix
        )
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Unrelated"),
            originalFolderName: "Unrelated",
            displayTitle: "Unrelated",
            previewCandidates: [preview]
        )
        let index = MusicSearchIndex(songs: [song])

        let result = try XCTUnwrap(index.searchResults("v3 mx").first)
        XCTAssertTrue(result.matchSummary.contains("fuzzy preview file"))
        XCTAssertFalse(result.matchSummary.contains("fuzzy text"))
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
