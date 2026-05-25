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
}
