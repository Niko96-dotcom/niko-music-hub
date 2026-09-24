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
        XCTAssertEqual(index.search("ranking preview").first?.displayTitle, "Lab Song")
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
            folderPath: URL(fileURLWithPath: "/tmp/GLÜHWURM"),
            originalFolderName: "GLÜHWURM",
            displayTitle: "GLÜHWURM"
        )
        let index = MusicSearchIndex(songs: [song])

        XCTAssertEqual(index.search("gluhwurm").count, 1)
        XCTAssertEqual(index.search("GLUHWURM").count, 1)
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

        let matches = index.searchResults("prjct fnd")
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
        XCTAssertTrue(matches.first?.matchSummary.contains("fuzzy project file") == true)
        XCTAssertFalse(matches.first?.matchSummary.contains("fuzzy text") == true)
    }

    func testFindsSongByFuzzyPreviewFileNameTokens() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let index = MusicSearchIndex(songs: result.songs)

        let matches = index.searchResults("ranking lab v3 mx")
        XCTAssertGreaterThanOrEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.song.displayTitle, "Lab Song")
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

    func testRepeatedSearchResultsPreserveOrderScoreAndExplanation() {
        // Parity guard for the benchmark digest: repeated queries must return
        // identical order, scores and explanations (ranking/fuzzy/diacritics).
        let songs = [
            Song(folderPath: URL(fileURLWithPath: "/tmp/Neon Hook"),
                 originalFolderName: "Neon Hook", displayTitle: "Neon Hook",
                 aliases: ["Demo"], collaboratorNames: ["Maria Klein"]),
            Song(folderPath: URL(fileURLWithPath: "/tmp/GLÜHWURM"),
                 originalFolderName: "GLÜHWURM", displayTitle: "GLÜHWURM"),
        ]
        let index = MusicSearchIndex(songs: songs)
        for query in ["neon", "neon hook", "gluhwurm", "maria", "zzzz absent"] {
            let first = index.searchResults(query)
            let second = index.searchResults(query)
            XCTAssertEqual(first.map(\.song.id), second.map(\.song.id), query)
            XCTAssertEqual(first.map(\.score), second.map(\.score), query)
            XCTAssertEqual(first.map(\.matchSummary), second.map(\.matchSummary), query)
        }
    }

    func testAsciiICasePairsMatchThroughSearchIndex() {
        // Turkish hosts fold ASCII "I" to dotless "ı" with Locale.current, which
        // split "MIX"/"mix". Search normalization must stay stable so indexed
        // metadata and queries agree regardless of host locale.
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/NEON MIX"),
            originalFolderName: "NEON MIX",
            displayTitle: "NEON MIX"
        )
        let index = MusicSearchIndex(songs: [song])

        XCTAssertEqual(MusicSearchMatcher.normalize("I"), "i")
        XCTAssertEqual(MusicSearchMatcher.normalize("i"), "i")
        XCTAssertEqual(MusicSearchMatcher.normalize("NEON MIX"), "neonmix")
        for query in ["neon mix", "NEON MIX", "Neon Mix", "mix", "MIX", "neon", "NEON"] {
            XCTAssertEqual(index.search(query).count, 1, "query: \(query)")
        }
    }

    func testMixedTitleAsciiCaseMatchesThroughSearchIndex() {
        let bigCity = Song(
            folderPath: URL(fileURLWithPath: "/tmp/BIG CITY NIGHTS"),
            originalFolderName: "BIG CITY NIGHTS",
            displayTitle: "BIG CITY NIGHTS"
        )
        let silkRoad = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Silk Road"),
            originalFolderName: "Silk Road",
            displayTitle: "Silk Road"
        )
        let index = MusicSearchIndex(songs: [bigCity, silkRoad])

        XCTAssertEqual(index.search("big city nights").count, 1)
        XCTAssertEqual(index.search("BIG CITY NIGHTS").count, 1)
        XCTAssertEqual(index.search("Big City Nights").first?.displayTitle, "BIG CITY NIGHTS")
        XCTAssertEqual(index.search("silk road").first?.displayTitle, "Silk Road")
        XCTAssertEqual(index.search("SILK ROAD").first?.displayTitle, "Silk Road")
    }

    func testDiacriticMatchingSurvivesStableLocaleNormalization() {
        let gluhwurm = Song(
            folderPath: URL(fileURLWithPath: "/tmp/GLÜHWURM"),
            originalFolderName: "GLÜHWURM",
            displayTitle: "GLÜHWURM"
        )
        let cafe = Song(
            folderPath: URL(fileURLWithPath: "/tmp/Café Noir"),
            originalFolderName: "Café Noir",
            displayTitle: "Café Noir"
        )
        let index = MusicSearchIndex(songs: [gluhwurm, cafe])

        XCTAssertEqual(index.search("gluhwurm").count, 1)
        XCTAssertEqual(index.search("GLUHWURM").count, 1)
        XCTAssertEqual(index.search("GLÜHWURM").count, 1)
        XCTAssertEqual(index.search("cafe noir").first?.displayTitle, "Café Noir")
        XCTAssertEqual(index.search("CAFÉ NOIR").first?.displayTitle, "Café Noir")
        // Ranking still prefers title matches: exact diacritic query ranks first.
        XCTAssertEqual(index.search("cafe").first?.displayTitle, "Café Noir")
    }

    func testTurkishSystemFoldingDivergesWhileSearchNormalizationStaysStable() {
        // Documents the host risk without mutating the global user locale:
        // explicit tr_TR folding maps "I" to dotless "ı", while the search
        // normalizer keeps the stable ASCII pair. Uses real index search for
        // the stable side.
        let turkishFolded = "I".folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "tr_TR")
        )
        XCTAssertTrue(
            turkishFolded.contains("ı"),
            "expected tr_TR to expose the dotless-I risk, got: \(turkishFolded)"
        )
        XCTAssertEqual(MusicSearchMatcher.normalize("I"), "i")

        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/NEON MIX"),
            originalFolderName: "NEON MIX",
            displayTitle: "NEON MIX"
        )
        let index = MusicSearchIndex(songs: [song])
        XCTAssertEqual(index.search("neon mix").count, 1)
        XCTAssertEqual(index.search("NEON MIX").count, 1)
    }
}
