import AppCore
import XCTest

final class HelperToolsHealthStripModelTests: XCTestCase {
    func testMissingHelpersIncludeDemucs() {
        let snapshot = HelperToolsHealthStripModel.make(
            ytDlp: .missing,
            ffmpeg: .missing,
            demucsMLX: .missing
        )

        XCTAssertEqual(snapshot.items.map(\.label), ["yt-dlp", "FFmpeg", "demucs-mlx"])
        XCTAssertTrue(snapshot.items.allSatisfy(\.needsSetup))
        XCTAssertTrue(snapshot.anyNeedsSetup)
    }

    func testReadyHelpersDoNotNeedSetup() {
        let snapshot = HelperToolsHealthStripModel.make(
            ytDlp: .available(version: "2024.01.01"),
            ffmpeg: .available(version: "7.0"),
            demucsMLX: .available(version: "demucs-mlx")
        )

        XCTAssertEqual(snapshot.items.map(\.label), ["yt-dlp", "FFmpeg", "demucs-mlx"])
        XCTAssertFalse(snapshot.anyNeedsSetup)
        XCTAssertTrue(snapshot.items.allSatisfy { !$0.needsSetup })
    }
}
