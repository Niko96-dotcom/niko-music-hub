import XCTest
@testable import NikoMusicCore

/// Wave A acceptance: production maturity ranking, stem/drum demotion, title inference.
final class WaveAPreviewAndTitleTests: XCTestCase {
    func test90sRavePrefersMasterOverSessionBounce() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let song = try XCTUnwrap(result.songs.first { $0.originalFolderName == "90s Rave" })
        let main = try XCTUnwrap(song.previewCandidates.first)

        XCTAssertEqual(song.displayTitle, "Graffiti")
        XCTAssertEqual(main.fileName, "Graffiti master.wav")
        XCTAssertTrue(main.confidenceReasons.contains("maturity:master"))
    }

    func testAnneMonstersPrefersFullMixOverDrums() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let song = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Anne Monsters" })
        let main = try XCTUnwrap(song.previewCandidates.first)

        XCTAssertEqual(song.displayTitle, "Anne Monsters")
        XCTAssertEqual(main.fileName, "Anne Monsters master mix.wav")
        XCTAssertFalse(main.fileName.lowercased().contains("drum"))
    }

    func testPreviewRankingLabUsesInferredDisplayTitle() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let song = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Preview Ranking Lab" })
        XCTAssertEqual(song.displayTitle, "Lab Song")
    }
}
