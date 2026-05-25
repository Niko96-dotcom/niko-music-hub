import XCTest
@testable import NikoMusicCore

final class MusicSearchIndexTests: XCTestCase {
    func testTokensSplitOnWhitespaceBeforeStrippingPunctuation() {
        XCTAssertEqual(MusicSearchMatcher.tokens(from: "neon hk"), ["neon", "hk"])
        XCTAssertEqual(MusicSearchMatcher.tokens(from: "  neon   hk  "), ["neon", "hk"])
        XCTAssertEqual(MusicSearchMatcher.tokens(from: "neon-hook"), ["neon", "hook"])
    }

    func testSpacedQueryRequiresDistinctTokensNotConcatenatedFuzzy() {
        let neonOnly = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Neon"),
            originalFolderName: "Neon",
            displayTitle: "Neon"
        )
        let hkOnly = Song(
            folderPath: URL(fileURLWithPath: "/tmp/HK"),
            originalFolderName: "HK",
            displayTitle: "HK"
        )
        let index = MusicSearchIndex(songs: [neonOnly, hkOnly])

        XCTAssertTrue(index.search("neon hk").isEmpty)
    }

    func testFindsNeonHookByTitleAndMixdownFilename() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        var index = MusicSearchIndex()
        index.rebuild(from: result.songs)

        XCTAssertEqual(index.search("Neon Hook").count, 1)
        XCTAssertFalse(index.search("Neon Hook v3").isEmpty)
    }

    func testTokenizedQueryMatchesWordsInAnyOrder() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)

        XCTAssertEqual(index.search("hook neon").count, 1)
        XCTAssertEqual(index.search("ranking preview").first?.displayTitle, "Preview Ranking Lab")
    }

    func testPunctuationInsensitiveQuery() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)

        XCTAssertEqual(index.search("neon-hook").count, 1)
    }

    func testDiacriticInsensitiveQuery() {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/BLÜMCHEN"),
            originalFolderName: "BLÜMCHEN",
            displayTitle: "BLÜMCHEN"
        )
        let index = MusicSearchIndex(songs: [song])

        XCTAssertEqual(index.search("blumchen").count, 1)
        XCTAssertEqual(index.search("BLUMCHEN").count, 1)
    }

    func testSubsequenceFuzzyMatchToleratesMinorTypos() {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Neon Hook"),
            originalFolderName: "Neon Hook",
            displayTitle: "Neon Hook"
        )
        let index = MusicSearchIndex(songs: [song])

        XCTAssertEqual(index.search("neohok").count, 1)
        XCTAssertEqual(index.search("neon hk").count, 1)
    }

    func testAllTokensMustMatch() {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Neon Hook"),
            originalFolderName: "Neon Hook",
            displayTitle: "Neon Hook"
        )
        let index = MusicSearchIndex(songs: [song])

        XCTAssertTrue(index.search("neon missing").isEmpty)
    }

    func testRanksDisplayTitleMatchesAboveFilenameOnlyMatches() {
        let titleMatch = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Alpha Prime"),
            originalFolderName: "Alpha Prime",
            displayTitle: "Alpha Prime"
        )
        let previewOnly = PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/Other/Mixdown/alpha prime mix.wav"),
            fileName: "alpha prime mix.wav",
            folderRole: .mixdown,
            modifiedAt: .distantPast,
            detectedRole: .mainMix
        )
        let filenameOnlyMatch = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Other"),
            originalFolderName: "Other",
            displayTitle: "Other",
            previewCandidates: [previewOnly]
        )
        let index = MusicSearchIndex(songs: [filenameOnlyMatch, titleMatch])

        XCTAssertEqual(index.search("alpha prime").first?.displayTitle, "Alpha Prime")
    }

    func testFindsSongByScanWarningToken() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)

        let matches = index.search("project")
        XCTAssertEqual(matches.first?.displayTitle, "Broken Folder Example")
    }

    func testFindsSongByFuzzyScanWarningToken() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)

        let matches = index.searchResults("ncpr fnd")
        XCTAssertEqual(matches.first?.song.displayTitle, "Broken Folder Example")
        XCTAssertTrue(matches.first?.matchSummary.contains("fuzzy scan warning") == true)
        XCTAssertFalse(matches.first?.matchSummary.contains("fuzzy text") == true)
    }

    func testFindsSongBySidecarNotesToken() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)

        XCTAssertEqual(index.search("only").first?.displayTitle, "Broken Folder Example")
    }

    func testFindsSongByFuzzySidecarNotesToken() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)

        let matches = index.searchResults("nts nly")
        XCTAssertEqual(matches.first?.song.displayTitle, "Broken Folder Example")
        XCTAssertTrue(matches.first?.matchSummary.contains("fuzzy song note") == true)
    }

    func testFindsSongByFuzzyFolderNameToken() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)

        let matches = index.searchResults("brkn fld")
        XCTAssertEqual(matches.first?.song.displayTitle, "Broken Folder Example")
        XCTAssertTrue(matches.first?.matchSummary.contains("fuzzy folder") == true)
        XCTAssertFalse(matches.first?.matchSummary.contains("fuzzy text") == true)
    }

    func testFindsSongByFuzzyCPRFileNameToken() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)

        let matches = index.searchResults("neohkv2")
        XCTAssertEqual(matches.first?.song.displayTitle, "Neon Hook")
        XCTAssertTrue(matches.first?.matchSummary.contains("fuzzy CPR file") == true)
        XCTAssertFalse(matches.first?.matchSummary.contains("fuzzy text") == true)
    }

    func testFindsSongByFuzzyPreviewFileNameTokens() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)

        let matches = index.searchResults("v3 mx")
        XCTAssertEqual(matches.first?.song.displayTitle, "Preview Ranking Lab")
        XCTAssertTrue(matches.first?.matchSummary.contains("fuzzy preview file") == true)
        XCTAssertFalse(matches.first?.matchSummary.contains("fuzzy text") == true)
    }

    func testRanksExactTitleTokenAboveFuzzyTitleMatch() {
        let exact = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Neon Hook"),
            originalFolderName: "Neon Hook",
            displayTitle: "Neon Hook"
        )
        let fuzzyOnly = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Neohok Band"),
            originalFolderName: "Neohok Band",
            displayTitle: "Neohok Band"
        )
        let index = MusicSearchIndex(songs: [fuzzyOnly, exact])

        XCTAssertEqual(index.search("neon").first?.displayTitle, "Neon Hook")
        XCTAssertEqual(index.search("neohok").first?.displayTitle, "Neohok Band")
    }
}
