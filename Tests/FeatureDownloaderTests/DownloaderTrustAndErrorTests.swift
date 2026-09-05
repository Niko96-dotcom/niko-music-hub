@testable import FeatureDownloader
import XCTest

final class DownloaderTrustAndErrorTests: XCTestCase {
    func testTrustNoticeIsDisplayedInView() {
        XCTAssertEqual(
            DownloaderCopy.trustNotice,
            "Downloads are for material you are allowed to access and save."
        )
    }

    func testSourceURLIsDisplayedBeforeDownload() {
        XCTAssertEqual(DownloaderCopy.sourceLabel, "Source")
    }

    func testOutputFolderIsDisplayedBeforeDownload() {
        XCTAssertEqual(DownloaderCopy.destinationLabel, "Output folder")
    }

    func testDownloadButtonIsOnlyStartTrigger() {
        XCTAssertEqual(DownloaderCopy.download, "Download")
        XCTAssertEqual(DownloaderCopy.clear, "Clear")
    }

    func testToolLabelIsDownloaderNotPromotional() {
        XCTAssertEqual(DownloaderCopy.toolLabel, "Downloader")
    }

    func testErrorMessagesAreActionable() {
        XCTAssertEqual(DownloaderCopy.missingYtDlp, "yt-dlp is required. Choose yt-dlp in Settings.")
        XCTAssertEqual(
            DownloaderCopy.unsupportedURL,
            "This URL is not supported or yt-dlp could not access it."
        )
    }

    func testRetryableErrorHasGuidance() {
        XCTAssertEqual(DownloaderCopy.retryableError, "Download failed (will retry): ")
        XCTAssertEqual(DownloaderCopy.permanentError, "Download failed (permanent): ")
    }

    @MainActor
    func testHTTP403ErrorCardDoesNotClaimURLIsUnsupported() {
        let card = DownloaderView.errorCard(
            for: "Download failed: ERROR: unable to download video data: HTTP Error 403: Forbidden"
        )

        XCTAssertEqual(card.label, "Download Temporarily Blocked")
        XCTAssertEqual(card.category, .conversionFile)
    }

    @MainActor
    func testGenericYtDlpErrorDoesNotClaimURLIsUnsupported() {
        let card = DownloaderView.errorCard(for: "Download failed: ERROR: remote server closed the connection")

        XCTAssertEqual(card.label, "Download Failed")
        XCTAssertEqual(card.category, .conversionFile)
    }

    func testCopyStringsAreNotEmpty() {
        XCTAssertFalse(DownloaderCopy.toolLabel.isEmpty)
        XCTAssertFalse(DownloaderCopy.trustNotice.isEmpty)
        XCTAssertFalse(DownloaderCopy.sourceLabel.isEmpty)
        XCTAssertFalse(DownloaderCopy.destinationLabel.isEmpty)
        XCTAssertFalse(DownloaderCopy.download.isEmpty)
    }
}
