import XCTest
@testable import NikoMusicCore

final class PreviewRankingExplainabilityTests: XCTestCase {
    func testMapsConfidenceReasonsToReadableLabels() {
        let summary = PreviewRankingExplainability.summary(
            from: ["role:full-mix", "folder:mixdown", "version:v3", "extension:wav", "duration:plausible", "recency"]
        )
        XCTAssertTrue(summary.contains("full mix"))
        XCTAssertTrue(summary.contains("mixdown"))
        XCTAssertTrue(summary.contains("v3"))
        XCTAssertTrue(summary.contains("wav"))
        XCTAssertTrue(summary.contains("plausible length"))
        XCTAssertFalse(summary.contains("recency"))
    }

    func testMainPreviewSummaryForRankingLabFixture() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let lab = try XCTUnwrap(result.songs.first { $0.displayTitle == "Preview Ranking Lab" })
        let summary = try XCTUnwrap(PreviewRankingExplainability.mainPreviewSummary(for: lab))

        XCTAssertTrue(summary.contains("Lab Song v3 mix.wav"))
        XCTAssertTrue(summary.contains("v3"))
        XCTAssertTrue(summary.contains("wav"))
        XCTAssertFalse(summary.lowercased().contains("too short"))
    }
}
