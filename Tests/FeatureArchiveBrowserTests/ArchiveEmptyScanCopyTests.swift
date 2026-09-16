import XCTest

final class ArchiveEmptyScanCopyTests: XCTestCase {
    func testEmptyScanningCopyDoesNotClaimStreaming() throws {
        let board = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBoardView.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            board.contains("Songs already in the cache stay visible."),
            "Empty-board scanning copy must explain cache visibility (NMH-044)"
        )
        XCTAssertFalse(
            board.contains("Songs will appear on the board as the scan finds them."),
            "Empty-board copy must not claim songs stream in during scan (NMH-044)"
        )
    }
}
