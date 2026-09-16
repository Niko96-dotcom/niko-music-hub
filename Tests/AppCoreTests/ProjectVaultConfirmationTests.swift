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
}
