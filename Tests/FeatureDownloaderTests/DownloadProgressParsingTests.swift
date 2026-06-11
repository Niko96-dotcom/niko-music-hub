@testable import FeatureDownloader
import XCTest

final class DownloadProgressParsingTests: XCTestCase {
    func testParsesNIKOProgressMarker() {
        XCTAssertEqual(YtDlpDownloader.parseProgressPercentage(from: "NIKO_PROGRESS: 45.2%"), 45.2)
        XCTAssertEqual(YtDlpDownloader.parseProgressPercentage(from: "NIKO_PROGRESS:100%"), 100.0)
        XCTAssertEqual(YtDlpDownloader.parseProgressPercentage(from: "NIKO_PROGRESS: 10.0%"), 10.0)
    }

    func testParseNormalizedProgressFromNIKOProgressMarker() {
        XCTAssertEqual(DownloaderUseCase.parseProgress(from: "NIKO_PROGRESS: 45.2%") ?? -1, 0.452, accuracy: 0.0001)
    }

    func testParsesProgressPercentage() {
        let line = "[download] 45.2% of 12.5M at 1.2MiB/s ETA 00:10"
        XCTAssertEqual(YtDlpDownloader.parseProgressPercentage(from: line), 45.2)
    }

    func testLogsInfoLines() {
        let progressLine = "[download] 10% of 100M at 1.0MiB/s ETA 00:09"
        let infoLine = "[info] Downloading playlist: example_playlist"
        let errorLine = "ERROR: unable to download"

        XCTAssertNotNil(YtDlpDownloader.parseProgressPercentage(from: progressLine))
        XCTAssertNil(YtDlpDownloader.parseProgressPercentage(from: infoLine))
        XCTAssertNil(YtDlpDownloader.parseProgressPercentage(from: errorLine))
    }

    func testHandlesMultiplePercentageFormats() {
        let full = "[download] 100.0% of 1.5G in 00:30"
        let partial = "[download] 50% of 2.3M"
        let decimal = "[download] 33.3% of 10.0M"

        XCTAssertEqual(YtDlpDownloader.parseProgressPercentage(from: full), 100.0)
        XCTAssertEqual(YtDlpDownloader.parseProgressPercentage(from: partial), 50.0)
        XCTAssertEqual(YtDlpDownloader.parseProgressPercentage(from: decimal), 33.3)
    }

    func testNonDownloadLinesReturnNil() {
        let nonProgressLines = [
            "[ExtractAudio] Extracting audio stream",
            "WARNING: unable to obtain video dimensions",
            "[download] Destination: /path/to/file.mp3",
            "ERROR: content too short"
        ]
        for line in nonProgressLines {
            XCTAssertNil(
                YtDlpDownloader.parseProgressPercentage(from: line),
                "Should return nil for: \(line)"
            )
        }
    }
}
