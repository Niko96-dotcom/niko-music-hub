@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import ProjectVaultRuntime
import XCTest

/// The Vault dialogs owner on its own: only the current capture presents its dialog, cancelling
/// one song's capture leaves another song's dialog, and one restore sheet loads at a time.
@MainActor
final class ArchiveVaultDialogsModelTests: XCTestCase {
    private func confirmation(for songID: String) -> ProjectVaultArchiveConfirmation {
        ProjectVaultArchiveConfirmation(
            songID: songID, songTitle: songID, trigger: .manual,
            willRemoveActiveCopy: false, independentBackupConfirmed: true, authorization: nil
        )
    }

    /// Starts a capture whose task does nothing and returns its generation.
    private func begin(_ dialogs: ArchiveVaultDialogsModel, songID: String) -> UInt64 {
        var started: UInt64 = 0
        dialogs.beginCapture(songID: songID) { generation in
            started = generation
            return Task {}
        }
        return started
    }

    func testASupersededCaptureNeverPresents() {
        let dialogs = ArchiveVaultDialogsModel()
        let first = begin(dialogs, songID: "a")
        let second = begin(dialogs, songID: "b")

        dialogs.presentConfirmation(confirmation(for: "a"), generation: first)
        XCTAssertNil(dialogs.pendingArchiveConfirmation, "a late result of the first capture shows nothing")

        dialogs.presentConfirmation(confirmation(for: "b"), generation: second)
        XCTAssertEqual(dialogs.pendingArchiveConfirmation?.songID, "b")
        XCTAssertNil(dialogs.captureSongID, "presenting ends the capture")
    }

    func testCancellingAnotherSongsCaptureKeepsThisDialog() {
        let dialogs = ArchiveVaultDialogsModel()
        let generation = begin(dialogs, songID: "a")
        dialogs.presentConfirmation(confirmation(for: "a"), generation: generation)

        dialogs.cancelCapture(for: "b")
        XCTAssertEqual(dialogs.pendingArchiveConfirmation?.songID, "a")

        dialogs.cancelCapture(for: "a")
        XCTAssertNil(dialogs.pendingArchiveConfirmation)
    }

    func testAStartedCaptureSupersedesTheShownDialog() {
        let dialogs = ArchiveVaultDialogsModel()
        let generation = begin(dialogs, songID: "a")
        dialogs.presentConfirmation(confirmation(for: "a"), generation: generation)

        _ = begin(dialogs, songID: "b")

        XCTAssertNil(dialogs.pendingArchiveConfirmation)
        XCTAssertEqual(dialogs.captureSongID, "b")
    }

    func testOneRestoreOptionsLoadAtATime() {
        let dialogs = ArchiveVaultDialogsModel()

        XCTAssertTrue(dialogs.beginRestoreOptionsLoad())
        XCTAssertFalse(dialogs.beginRestoreOptionsLoad())
        dialogs.endRestoreOptionsLoad()
        XCTAssertTrue(dialogs.beginRestoreOptionsLoad())
    }

    func testEveryDialogCountsAsPending() {
        let dialogs = ArchiveVaultDialogsModel()
        XCTAssertFalse(dialogs.hasPendingDialog)

        dialogs.askToStopTransfer()
        XCTAssertTrue(dialogs.hasPendingDialog)
        dialogs.closeStopTransferQuestion()

        let generation = begin(dialogs, songID: "a")
        dialogs.presentConfirmation(confirmation(for: "a"), generation: generation)
        XCTAssertTrue(dialogs.hasPendingDialog)
        dialogs.closeConfirmation()
        XCTAssertFalse(dialogs.hasPendingDialog)
    }

    func testQuitStopsTheVaultForTheRestOfTheRun() {
        let dialogs = ArchiveVaultDialogsModel()
        XCTAssertFalse(dialogs.stoppedForQuit)

        dialogs.markStoppedForQuit()

        XCTAssertTrue(dialogs.stoppedForQuit)
    }
}
