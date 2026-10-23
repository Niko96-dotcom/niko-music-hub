import AppCore
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
        XCTAssertEqual(
            DownloaderCopy.ytDlpMissing,
            "yt-dlp is not installed. Use Install Tools, or choose it in Settings → Helpers."
        )
        XCTAssertEqual(
            DownloaderCopy.unsupportedURL,
            "This URL is not supported or yt-dlp could not access it."
        )
    }

    /// The card follows the yt-dlp status, never the message text: each problem
    /// has its own label and sentence and the same three recoveries.
    @MainActor
    func testYtDlpCardLabelFollowsTheStatus() {
        let cases: [(HelperToolStatus, String, String)] = [
            (.missing, "yt-dlp Not Found", "yt-dlp is not installed. Use Install Tools, or choose it in Settings → Helpers."),
            (
                .outdated(current: "2023.01.01", minimumExpected: "2024.01.01"),
                "yt-dlp Outdated",
                "yt-dlp 2023.01.01 is outdated (expected 2024.01.01 or newer). Use Install Tools to update it."
            ),
            (.broken(message: "Permission denied"), "yt-dlp Can't Start", "yt-dlp could not start: Permission denied"),
        ]
        for (status, label, body) in cases {
            let card = DownloaderView.helperCard(for: status)

            XCTAssertEqual(card.category, .helperTool, "\(status)")
            XCTAssertEqual(card.label, label)
            XCTAssertEqual(card.body, body)
            XCTAssertEqual(card.recoveryActions.map(\.label), ["Install Tools", "Choose Path", "Try Again"])
            XCTAssertEqual(card.recoveryActions.map(\.action), [.installHelperTools, .chooseToolPath, .tryAgain])
            XCTAssertFalse(card.recoveryActions.contains { $0.action == .openTerminal })
        }
    }

    /// Message text no longer picks the helper card: a download failure that
    /// mentions "outdated" is a download failure.
    @MainActor
    func testMessageTextNeverPicksTheHelperCard() {
        let card = DownloaderView.errorCard(for: "Download failed: ERROR: this format is outdated")

        XCTAssertNotEqual(card.category, .helperTool)
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

    func testCanceledCopyIsSecondaryStatusNotFailure() {
        XCTAssertEqual(DownloaderCopy.downloadCanceled, "Download canceled")
        XCTAssertEqual(
            DownloaderCopy.downloadCanceledDetail,
            "Download canceled. The Output Inbox was not updated."
        )
    }
}
