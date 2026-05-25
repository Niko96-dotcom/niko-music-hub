import XCTest
@testable import NikoMusicCore

final class PreviewConfidenceRankerTests: XCTestCase {
    func testNeonHookPrefersFullMixOverInstrumental() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })
        let main = try XCTUnwrap(neon.previewCandidates.first)
        XCTAssertFalse(main.fileName.lowercased().contains("instr"))
        XCTAssertTrue(main.fileName.contains("v3") || main.fileName.lowercased().contains("mix"))
    }

    func testSecondSongPrefersMixdownOverInstr() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let second = try XCTUnwrap(result.songs.first { $0.displayTitle == "Second Song" })
        let main = try XCTUnwrap(second.previewCandidates.first)
        XCTAssertTrue(main.fileName.lowercased().contains("mixdown"))
    }
}
