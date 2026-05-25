import XCTest
@testable import NikoMusicCore

final class MusicSearchIndexTests: XCTestCase {
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
}
