import AppCore
import XCTest

final class ProjectVaultConfirmationTests: XCTestCase {
    func testArchiveNowCopyStatesIndependentBackup() {
        let title = "Test Song"
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.archiveNowMessage(
                songTitle: title,
                independentBackupConfirmed: true
            ),
            "Niko Music Hub will copy “Test Song” to Project Vault and verify the copy. It will then permanently delete the Active Projects folder. Deleted files do not go to the Trash. You can later use Get Local & Open to copy a verified generation back into Active Projects. Settings currently records that you protect the Archive with an independent backup."
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.archiveNowMessage(
                songTitle: title,
                independentBackupConfirmed: false
            ),
            "Niko Music Hub will copy “Test Song” to Project Vault and verify the copy. Removing the Active Projects folder also requires the independent-backup setting. If that setting is off, the copy is kept and the Active folder stays. You can later use Get Local & Open from a verified generation."
        )
    }

    func testArchiveNowMessageMentionsIndependentBackupWhenConfirmed() {
        let message = ProjectVaultConfirmationCopy.archiveNowMessage(
            songTitle: "Test Song",
            independentBackupConfirmed: true
        )
        XCTAssertTrue(
            message.contains("Settings currently records that you protect the Archive with an independent backup"),
            "Archive Now must restate the independent-backup gate rather than treating the checkbox as the deletion itself."
        )
    }

    func testIndependentBackupSettingsCopyKeepsCheckboxAsGate() {
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.independentBackupToggleTitle,
            "I protect the Archive with an independent backup"
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.independentBackupToggleFooter,
            "Archive Now can delete the Active Projects folder only when this is on and the other safety checks pass. Turning this on does not delete anything. Niko Music Hub still asks before Archive Now."
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.vaultEnabledSuccessMessage,
            "Project Vault is on. Private beta automation creates copies only. Archive Now can remove the Active copy after you confirm, and only when independent backup is recorded and the other safety checks pass."
        )
    }

    func testWorkflowDoneCopyStatesRemovalAndBackup() {
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.workflowDoneTitle(willRemoveActiveCopy: false),
            "Archive this project?"
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.workflowDoneTitle(willRemoveActiveCopy: true),
            "Archive and remove the Active copy?"
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.workflowDoneMessage(
                songTitle: "Test Song",
                willRemoveActiveCopy: false
            ),
            "Moving “Test Song” to Done starts a Project Vault archive. The Active Projects folder stays in place. You can change the workflow status later from the card menu or with Edit → Undo."
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.workflowDoneMessage(
                songTitle: "Test Song",
                willRemoveActiveCopy: true
            ),
            "Moving “Test Song” to Done starts a Project Vault archive. After a verified copy, Niko Music Hub permanently deletes the Active Projects folder because Settings records an independent backup and friends rollout is on. Deleted files do not go to the Trash. Recovery is Get Local & Open."
        )
        XCTAssertEqual(ProjectVaultConfirmationCopy.workflowDoneCancelTitle, "Keep Status")
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.workflowDoneConfirmTitle(willRemoveActiveCopy: false),
            "Archive and Mark Done"
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.workflowDoneConfirmTitle(willRemoveActiveCopy: true),
            "Archive"
        )
    }
}
