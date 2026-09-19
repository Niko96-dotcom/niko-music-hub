import Foundation



/// UI-facing confirmation payload. `songTitle` is display-only and is never an
/// identity input: the bound V3 authorization
/// (`ProjectVaultArchiveAuthorization`) deliberately carries no title and
/// binds source path + filesystem object, song/catalog identity, roots, trigger,
/// and destructiveness instead. The UI consumer owns passing the captured
/// authorization through confirmation, queue, and retries (including relaunch);
/// without that bound value the runtime performs a verified copy only.
public struct ProjectVaultArchiveConfirmation: Equatable, Sendable {
    public var songID: String
    public var songTitle: String
    public var trigger: ProjectVaultArchiveTrigger
    public var willRemoveActiveCopy: Bool
    public var independentBackupConfirmed: Bool
    /// The bound V3 authorization captured BEFORE the dialog was presented.
    /// The UI consumer retains this exact value through confirmation, queue
    /// closure, and bounded retries, and hands it to
    /// `archive(song:trigger:authorization:)`. It is never re-captured or
    /// strengthened at execution: a copy-only value stays copy-only even when
    /// live settings later become permissive, and any source/root/identity
    /// drift fails closed inside the runtime. `songTitle` above stays
    /// display-only; the authorization carries no title.
    public var authorization: ProjectVaultArchiveAuthorization?

    public init(
        songID: String,
        songTitle: String,
        trigger: ProjectVaultArchiveTrigger,
        willRemoveActiveCopy: Bool,
        independentBackupConfirmed: Bool,
        authorization: ProjectVaultArchiveAuthorization? = nil
    ) {
        self.songID = songID
        self.songTitle = songTitle
        self.trigger = trigger
        self.willRemoveActiveCopy = willRemoveActiveCopy
        self.independentBackupConfirmed = independentBackupConfirmed
        self.authorization = authorization
    }
}

public enum ProjectVaultConfirmationCopy: Sendable {
    public static func archiveNowTitle(willRemoveActiveCopy: Bool) -> String {
        willRemoveActiveCopy ? "Archive and remove the Active copy?" : "Archive this project?"
    }

    public static func archiveNowConfirmTitle(willRemoveActiveCopy: Bool) -> String {
        willRemoveActiveCopy ? "Archive" : "Archive Copy"
    }

    /// Bound Archive Now message. The dialog must agree the captured token
    /// ceiling (`pending.willRemoveActiveCopy`): only a token that actually
    /// permits removal may promise deletion, and the independent-backup
    /// restatement appears only in that removal case. A copy-only token keeps
    /// the Active folder regardless of the live backup flag, so it never
    /// claims a delete even when backup is on but removal was gated
    /// (Keep Local, Emergency Stop, or a removal-capture fallback).
    public static func archiveNowMessage(
        songTitle: String,
        willRemoveActiveCopy: Bool,
        independentBackupConfirmed: Bool
    ) -> String {
        if willRemoveActiveCopy {
            return "Niko Music Hub will copy “\(songTitle)” to Project Vault and verify the copy. It will then permanently delete the Active Projects folder. Deleted files do not go to the Trash. You can later use Get Local & Open to copy a verified generation back into Active Projects. Settings currently records that you protect the Archive with an independent backup."
        }
        if !independentBackupConfirmed {
            return "Niko Music Hub will copy “\(songTitle)” to Project Vault and verify the copy. Removing the Active Projects folder also requires the independent-backup setting. If that setting is off, the copy is kept and the Active folder stays. You can later use Get Local & Open from a verified generation."
        }
        return "Niko Music Hub will copy “\(songTitle)” to Project Vault and verify the copy. The Active Projects folder stays in place. You can later use Get Local & Open from a verified generation."
    }

    /// Compatibility overload. Preserved so existing call sites compile;
    /// it restates the legacy mapping where the backup flag stood in for the
    /// ceiling. Bound UI must call the
    /// `archiveNowMessage(songTitle:willRemoveActiveCopy:independentBackupConfirmed:)`
    /// overload with `pending.willRemoveActiveCopy` instead.
    public static func archiveNowMessage(
        songTitle: String,
        independentBackupConfirmed: Bool
    ) -> String {
        archiveNowMessage(
            songTitle: songTitle,
            willRemoveActiveCopy: independentBackupConfirmed,
            independentBackupConfirmed: independentBackupConfirmed
        )
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

    public static let independentBackupToggleTitle = "I protect the Archive with an independent backup"

    public static let independentBackupToggleFooter =
        "Archive Now can delete the Active Projects folder only when this is on and the other safety checks pass. Turning this on does not delete anything. Niko Music Hub still asks before Archive Now."

    public static let vaultEnabledSuccessMessage =
        "Project Vault is on. Private beta automation creates copies only. Archive Now can remove the Active copy after you confirm, and only when independent backup is recorded and the other safety checks pass."

    /// Automatic-Done destructive-consent contract (V3). Marking a project
    /// Done without a bound per-operation authorization only ever creates a
    /// verified copy: neither the Done status, a relaunch, nor permissive
    /// settings imply approval to remove the Active copy. Removal requires an
    /// explicit Archive confirmation captured for that operation; undoing Done
    /// revokes the queued automation instead of deleting.
    public static let automaticDoneCopyOnlyContract =
        "Marking Done without an explicit Archive confirmation creates a verified copy only. The Active copy stays until you confirm its removal, and undoing Done revokes the queued archive."
}
