import XCTest
@testable import NikoMusicCore

final class ArchiveScanDiagnosticsSummaryTruncationFixtureTests: XCTestCase {
    func testSummaryTruncationFixtureProducesTruncatedSummaryLine() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.summaryTruncationRoot])
        let diagnostics = ArchiveScanDiagnosticsBuilder.build(result: result, roots: [CubaseFixtures.summaryTruncationRoot])

        XCTAssertEqual(diagnostics.songCount, 8)
        XCTAssertEqual(diagnostics.songsWithWarningsCount, 8)
        XCTAssertTrue(diagnostics.summaryLineSongWarningTitlesTruncated)
        XCTAssertEqual(diagnostics.summaryLineSongWarningTitlesOmittedCount, 3)
        XCTAssertTrue(diagnostics.summaryLine.contains("and 3 more"))
        XCTAssertTrue(diagnostics.summaryLine.contains("Summary Warning 01"))
        XCTAssertFalse(diagnostics.summaryLine.contains("Summary Warning 08"))
    }
}
