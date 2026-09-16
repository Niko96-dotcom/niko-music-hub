import Foundation

extension ProjectVaultArchiveTrigger: Equatable {}

public struct ProjectVaultArchiveConfirmation: Equatable, Sendable {
    public var songID: String
    public var songTitle: String
    public var trigger: ProjectVaultArchiveTrigger
    public var willRemoveActiveCopy: Bool
    public var independentBackupConfirmed: Bool

    public init(
        songID: String,
        songTitle: String,
        trigger: ProjectVaultArchiveTrigger,
        willRemoveActiveCopy: Bool,
        independentBackupConfirmed: Bool
    ) {
        self.songID = songID
        self.songTitle = songTitle
        self.trigger = trigger
        self.willRemoveActiveCopy = willRemoveActiveCopy
        self.independentBackupConfirmed = independentBackupConfirmed
    }
}

public enum ProjectVaultConfirmationCopy: Sendable {
    public static func archiveNowMessage(
        songTitle: String,
        independentBackupConfirmed: Bool
    ) -> String {
        if independentBackupConfirmed {
            return "Niko Music Hub will copy “\(songTitle)” to Project Vault and verify the copy. It will then permanently delete the Active Projects folder. Deleted files do not go to the Trash. You can later use Get Local & Open to copy a verified generation back into Active Projects. Settings currently records that you protect the Archive with an independent backup."
        }
        return "Niko Music Hub will copy “\(songTitle)” to Project Vault and verify the copy. Removing the Active Projects folder also requires the independent-backup setting. If that setting is off, the copy is kept and the Active folder stays. You can later use Get Local & Open from a verified generation."
    }

    public static let workflowDoneCancelTitle = "Keep Status"

    public static func workflowDoneConfirmTitle(willRemoveActiveCopy: Bool) -> String {
        willRemoveActiveCopy ? "Archive" : "Archive and Mark Done"
    }

    public static func workflowDoneTitle(willRemoveActiveCopy: Bool) -> String {
        willRemoveActiveCopy ? "Archive and remove the Active copy?" : "Archive this project?"
    }

    public static func workflowDoneMessage(
        songTitle: String,
        willRemoveActiveCopy: Bool
    ) -> String {
        if willRemoveActiveCopy {
            return "Moving “\(songTitle)” to Done starts a Project Vault archive. After a verified copy, Niko Music Hub permanently deletes the Active Projects folder because Settings records an independent backup and friends rollout is on. Deleted files do not go to the Trash. Recovery is Get Local & Open."
        }
        return "Moving “\(songTitle)” to Done starts a Project Vault archive. The Active Projects folder stays in place. You can change the workflow status later from the card menu or with Edit → Undo."
    }
}
