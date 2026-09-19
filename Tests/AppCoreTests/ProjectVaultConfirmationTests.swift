import AppCore
import Foundation
import NikoMusicCore
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

    func testArchiveNowChromeBoundToTokenCeiling() {
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.archiveNowTitle(willRemoveActiveCopy: true),
            "Archive and remove the Active copy?"
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.archiveNowTitle(willRemoveActiveCopy: false),
            "Archive this project?"
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.archiveNowConfirmTitle(willRemoveActiveCopy: true),
            "Archive"
        )
        XCTAssertEqual(
            ProjectVaultConfirmationCopy.archiveNowConfirmTitle(willRemoveActiveCopy: false),
            "Archive Copy"
        )
    }

    func testArchiveNowCopyOnlyTokenNeverPromisesDelete() {
        let gated = ProjectVaultConfirmationCopy.archiveNowMessage(
            songTitle: "Test Song",
            willRemoveActiveCopy: false,
            independentBackupConfirmed: true
        )
        XCTAssertFalse(gated.contains("permanently delete"), "a copy-only token must not promise deletion even with backup on")
        XCTAssertFalse(gated.contains("do not go to the Trash"))
        XCTAssertFalse(
            gated.contains("Settings currently records that you protect the Archive with an independent backup"),
            "the backup-gate restatement belongs to the removal case only"
        )
        XCTAssertTrue(gated.contains("stays in place"), "a copy-only token must state the Active folder stays")

        let removal = ProjectVaultConfirmationCopy.archiveNowMessage(
            songTitle: "Test Song",
            willRemoveActiveCopy: true,
            independentBackupConfirmed: true
        )
        XCTAssertTrue(removal.contains("permanently delete"))
        XCTAssertTrue(removal.contains("Settings currently records that you protect the Archive with an independent backup"))

        let backupOff = ProjectVaultConfirmationCopy.archiveNowMessage(
            songTitle: "Test Song",
            willRemoveActiveCopy: false,
            independentBackupConfirmed: false
        )
        XCTAssertFalse(backupOff.contains("permanently delete"))
        XCTAssertTrue(backupOff.contains("Active folder stays"))
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

    func testArchiveTriggerCodableMappingIsStable() throws {
        XCTAssertEqual(ProjectVaultArchiveTrigger(rawValue: "manual"), .manual)
        XCTAssertEqual(ProjectVaultArchiveTrigger(rawValue: "backupCopy"), .backupCopy)
        XCTAssertEqual(ProjectVaultArchiveTrigger(rawValue: "workflowDone"), .workflowDone)
        XCTAssertEqual(
            String(decoding: try JSONEncoder().encode(ProjectVaultArchiveTrigger.manual), as: UTF8.self),
            "\"manual\""
        )
    }

    func testArchiveAuthorizationCodableRoundTrip() throws {
        for trigger in [ProjectVaultArchiveTrigger.manual, .backupCopy, .workflowDone] {
            let authorization = ProjectVaultArchiveAuthorization(
                sourceCanonicalPath: "/Active/Synthetic Song",
                sourceFileSystemIdentity: ProjectVaultSourceFileSystemIdentity(device: 11, inode: 22),
                songID: "/Active/Synthetic Song",
                catalogProjectID: ProjectID(),
                activeRootID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                activeRootCanonicalPath: "/Active",
                activeRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity(device: 11, inode: 33),
                archiveRootID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
                archiveRootCanonicalPath: "/Archive",
                archiveRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity(device: 44, inode: 55),
                trigger: trigger,
                maximumDestructiveness: trigger == .backupCopy ? .copyOnly : .mayRemoveActiveCopy,
                authorizedAt: Date(timeIntervalSince1970: 123_456)
            )
            let data = try JSONEncoder().encode(authorization)
            XCTAssertEqual(try JSONDecoder().decode(ProjectVaultArchiveAuthorization.self, from: data), authorization)
        }
    }

    func testTamperedAuthorizationCopyNeverMatchesOriginal() throws {
        let authorization = ProjectVaultArchiveAuthorization(
            sourceCanonicalPath: "/Active/Synthetic Song",
            sourceFileSystemIdentity: ProjectVaultSourceFileSystemIdentity(device: 11, inode: 22),
            songID: "/Active/Synthetic Song",
            catalogProjectID: nil,
            activeRootID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            activeRootCanonicalPath: "/Active",
            activeRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity(device: 11, inode: 33),
            archiveRootID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            archiveRootCanonicalPath: "/Archive",
            archiveRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity(device: 44, inode: 55),
            trigger: .manual,
            maximumDestructiveness: .mayRemoveActiveCopy,
            authorizedAt: Date(timeIntervalSince1970: 123_456)
        )
        let data = try JSONEncoder().encode(authorization)
        var decoded = try JSONDecoder().decode(ProjectVaultArchiveAuthorization.self, from: data)
        XCTAssertEqual(decoded, authorization)
        decoded = ProjectVaultArchiveAuthorization(
            sourceCanonicalPath: decoded.sourceCanonicalPath,
            sourceFileSystemIdentity: decoded.sourceFileSystemIdentity,
            songID: decoded.songID,
            catalogProjectID: decoded.catalogProjectID,
            activeRootID: decoded.activeRootID,
            activeRootCanonicalPath: decoded.activeRootCanonicalPath,
            activeRootFileSystemIdentity: decoded.activeRootFileSystemIdentity,
            archiveRootID: decoded.archiveRootID,
            archiveRootCanonicalPath: decoded.archiveRootCanonicalPath,
            archiveRootFileSystemIdentity: decoded.archiveRootFileSystemIdentity,
            trigger: .backupCopy,
            maximumDestructiveness: .mayRemoveActiveCopy,
            authorizedAt: decoded.authorizedAt
        )
        XCTAssertNotEqual(decoded, authorization, "a trigger/backup-copy mismatch must never compare equal to a removal approval")
    }
}
