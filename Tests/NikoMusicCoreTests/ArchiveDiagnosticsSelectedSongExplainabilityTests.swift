import XCTest
@testable import NikoMusicCore

final class ArchiveDiagnosticsSelectedSongExplainabilityTests: XCTestCase {
    func testCprSummaryForNeonHook() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })
        XCTAssertEqual(
            ArchiveDiagnosticsSelectedSongExplainability.cprSummary(for: neon),
            "2 versions · latest Neon Hook.cpr"
        )
    }

    func testCprSummaryForBrokenFolder() throws {
        try CubaseFixtures.ensureGenerated()
        let result = try CubaseArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot])
        let broken = try XCTUnwrap(result.songs.first { $0.displayTitle == "Broken Folder Example" })
        XCTAssertEqual(
            ArchiveDiagnosticsSelectedSongExplainability.cprSummary(for: broken),
            "no CPR versions"
        )
    }
}
