@testable import FeatureDownloader
import XCTest

/// NMH-141 (TOOL-30): yt-dlp `--no-overwrites` skip must read as an
/// informational inbox status, not a generic network failure.
/// String/unit only; no network.
final class YtDlpAlreadyExistsCopyTests: XCTestCase {
    func testAlreadyExistsCopyString() {
        XCTAssertEqual(
            DownloaderCopy.alreadyExistsInInbox,
            "This file already exists in the Output Inbox."
        )
    }

    func testAlreadyDownloadedLineMapsToInboxCopy() {
        XCTAssertEqual(
            YtDlpDownloader.alreadyExistsCopy(
                for: "[download] /tmp/out/Some Title [abc123].mp4 has already been downloaded"
            ),
            DownloaderCopy.alreadyExistsInInbox
        )
        XCTAssertNil(
            YtDlpDownloader.alreadyExistsCopy(
                for: "[download]  42.5% of 10.00MiB at 1.00MiB/s ETA 00:05"
            )
        )
    }

    func testAlreadyDownloadedMarkerDetection() {
        XCTAssertTrue(
            YtDlpDownloader.containsAlreadyDownloadedMarker(
                "[download] relative/final.mp4 has already been downloaded"
            )
        )
        XCTAssertFalse(
            YtDlpDownloader.containsAlreadyDownloadedMarker(
                "[download] Destination: /tmp/out/final.mp4"
            )
        )
    }

    @MainActor
    func testViewModelDetectsSkipFromLogs() {
        XCTAssertTrue(
            DownloaderViewModel.isAlreadyDownloadedSkip(
                logEntries: ["[download] /tmp/out/Title [abc].mp4 has already been downloaded"],
                message: "No output files found after download."
            )
        )
        XCTAssertFalse(
            DownloaderViewModel.isAlreadyDownloadedSkip(
                logEntries: ["ERROR: unable to download video data: HTTP Error 403: Forbidden"],
                message: "Download failed: ERROR: unable to download video data: HTTP Error 403: Forbidden"
            )
        )
    }
}
