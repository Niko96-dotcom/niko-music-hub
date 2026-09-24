import AppCore
import XCTest

final class HubCancelCommandsTests: XCTestCase {
    func testCancelCopyMatchesHIGContract() {
        XCTAssertEqual(CancelCopy.cancelDownload, "Cancel Download")
        XCTAssertEqual(CancelCopy.cancelScan, "Cancel Scan")
        XCTAssertEqual(CancelCopy.cancelTransfer, "Cancel Transfer")
        XCTAssertEqual(
            CancelCopy.scanCanceled,
            "Scan canceled. Songs already in the catalog stay available."
        )
        XCTAssertEqual(CancelCopy.stopTransferTitle, "Stop this transfer?")
        XCTAssertEqual(
            CancelCopy.stopTransferMessage,
            "Niko Music Hub will stop the Project Vault transfer at the next safe point. Files already copied stay in the archive but are not verified until the transfer completes. If the Active Projects folder was already removed after verification, stopping does not restore it. Use Restore & Open or Recover Verified Project to review the verified archive."
        )
        XCTAssertEqual(CancelCopy.keepTransferring, "Keep Transferring")
        XCTAssertEqual(CancelCopy.stopTransfer, "Stop Transfer")
        XCTAssertFalse(CancelCopy.stopTransferTitle.contains("!"))
        XCTAssertFalse(CancelCopy.stopTransferMessage.contains("!"))
    }

    func testCommandPeriodCancelsForemostJob() throws {
        let commands = try SourceTestSupport.read("Sources/NikoMusicHub/Commands/HubCancelCommands.swift")
        XCTAssertTrue(commands.contains("keyboardShortcut(\".\", modifiers: .command)"))
        XCTAssertTrue(commands.contains("cancelForemostJob"))
        XCTAssertTrue(commands.contains("cancelEscapeTarget"))

        let app = try SourceTestSupport.read("Sources/NikoMusicHub/NikoMusicHubApp.swift")
        XCTAssertTrue(app.contains("HubCancelCommands("))

        let downloader = try SourceTestSupport.read("Sources/FeatureDownloader/DownloaderView.swift")
        XCTAssertTrue(downloader.contains("CancelCopy.cancelDownload"))
        XCTAssertTrue(downloader.contains("cancelDownload()"))
        XCTAssertFalse(downloader.contains("keyboardShortcut(.cancelAction)"))
        XCTAssertFalse(downloader.contains("keyboardShortcut(\".\", modifiers: .command)"))
        XCTAssertTrue(commands.contains("@FocusedValue(\\.hubShellCancelContext)"))
        XCTAssertTrue(commands.contains("@ObservedObject var jobStatusCenter"))

        let sidebar = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/ArchiveSidebarView.swift")
        XCTAssertTrue(sidebar.contains("CancelCopy.cancelScan"))
        XCTAssertTrue(sidebar.contains("cancelScan()"))

        let board = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/ArchiveBoardView.swift")
        XCTAssertTrue(board.contains("CancelCopy.cancelScan"))
        XCTAssertTrue(board.contains("cancelScan()"))

        let detail = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/SongDetailView.swift")
        XCTAssertTrue(detail.contains("CancelCopy.cancelTransfer"))
        XCTAssertTrue(detail.contains("requestStopActiveProjectVaultTransfer()"))

        let browser = try SourceTestSupport.read("Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift")
        XCTAssertTrue(browser.contains("CancelCopy.stopTransferTitle"))
        XCTAssertTrue(browser.contains("CancelCopy.keepTransferring"))
        XCTAssertTrue(browser.contains("CancelCopy.stopTransfer"))
        XCTAssertTrue(browser.contains("keyboardShortcut(.defaultAction)"))
        XCTAssertTrue(browser.contains("requestStopActiveProjectVaultTransfer"))
        XCTAssertTrue(browser.contains("confirmStopActiveProjectVaultTransfer"))
    }
}
