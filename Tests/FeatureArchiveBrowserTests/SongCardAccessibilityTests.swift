import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

final class SongCardAccessibilityTests: XCTestCase {
    func testSummaryIncludesStatusAndWarning() {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/fixture/song"),
            originalFolderName: "Neon Hook",
            displayTitle: "Neon Hook",
            scanWarnings: ["Missing mixdown"],
            workflowStatus: .prod
        )

        XCTAssertEqual(
            SongCardAccessibility.summary(song: song),
            "Neon Hook, Prod, Warning: Missing mixdown"
        )
    }

    func testSummaryWithoutWarningOmitsWarningClause() {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/fixture/song"),
            originalFolderName: "Neon Hook",
            displayTitle: "Neon Hook"
        )
        let summary = SongCardAccessibility.summary(song: song)

        XCTAssertEqual(summary, "Neon Hook, No Status")
        XCTAssertFalse(summary.contains("Warning:"))
    }
}
