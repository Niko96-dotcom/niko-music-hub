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
}
