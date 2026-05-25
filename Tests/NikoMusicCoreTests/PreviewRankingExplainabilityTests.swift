import XCTest
@testable import NikoMusicCore

final class PreviewRankingExplainabilityTests: XCTestCase {
    func testMapsConfidenceReasonsToReadableLabels() {
        let summary = PreviewRankingExplainability.summary(
            from: ["role:full-mix", "folder:mixdown", "version:v3", "extension:wav", "duration:plausible", "recency"],
            durationSeconds: 210
        )
        XCTAssertTrue(summary.contains("full mix"))
        XCTAssertTrue(summary.contains("mixdown"))
        XCTAssertTrue(summary.contains("v3"))
        XCTAssertTrue(summary.contains("wav"))
        XCTAssertTrue(summary.contains("plausible length (3:30)"))
        XCTAssertFalse(summary.contains("recency"))
    }

    func testDurationLabelsIncludeSecondsForTooShort() {
        let summary = PreviewRankingExplainability.summary(
            from: ["duration:too-short"],
            durationSeconds: 5
        )
        XCTAssertEqual(summary, "too short (5s)")
    }

    func testDurationLabelsIncludeSecondsForLongTake() {
        let summary = PreviewRankingExplainability.summary(
            from: ["duration:long"],
            durationSeconds: 720
        )
        XCTAssertEqual(summary, "long take (12:00)")
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
        XCTAssertTrue(summary.contains("plausible length (3:30)"))
        XCTAssertFalse(summary.lowercased().contains("too short"))
    }
}
