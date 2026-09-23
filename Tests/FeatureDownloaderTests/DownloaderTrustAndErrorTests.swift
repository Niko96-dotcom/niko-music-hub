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
            DownloaderCopy.missingYtDlp,
            "yt-dlp is required. Choose yt-dlp in Settings → Helpers."
        )
        XCTAssertEqual(
            DownloaderCopy.unsupportedURL,
            "This URL is not supported or yt-dlp could not access it."
        )
    }

    @MainActor
    func testMissingYtDlpCardOpensSettingsAndChoosePathNotTerminal() {
        let card = DownloaderView.errorCard(for: DownloaderCopy.missingYtDlp)

        XCTAssertEqual(card.category, .helperTool)
        XCTAssertEqual(
            card.recoveryActions.map(\.label),
            ["Install Tools", "Choose Path", "Try Again"]
        )
        XCTAssertEqual(
            card.recoveryActions.map(\.action),
            [.installHelperTools, .chooseToolPath, .tryAgain]
        )
        XCTAssertFalse(card.recoveryActions.contains { $0.action == .openTerminal })
        XCTAssertFalse(card.recoveryActions.contains { $0.label == "Open Terminal" })
        XCTAssertFalse(card.recoveryActions.contains { $0.label == "Retry" })
    }

    @MainActor
    func testOutdatedYtDlpCardUsesTheSameSettingsRecovery() {
        let message = DownloaderCopy.outdatedYtDlp(current: "2023.01.01", minimumExpected: "2024.01.01")
        let card = DownloaderView.errorCard(for: message)

        XCTAssertEqual(card.category, .helperTool)
        XCTAssertEqual(
            card.recoveryActions.map(\.action),
            [.installHelperTools, .chooseToolPath, .tryAgain]
        )
        XCTAssertFalse(card.recoveryActions.contains { $0.action == .openTerminal })
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

    func testCanceledCopyIsSecondaryStatusNotFailure() {
        XCTAssertEqual(DownloaderCopy.downloadCanceled, "Download canceled")
        XCTAssertEqual(
            DownloaderCopy.downloadCanceledDetail,
            "Download canceled. The Output Inbox was not updated."
        )
    }
}
