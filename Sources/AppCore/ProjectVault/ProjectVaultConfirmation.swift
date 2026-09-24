import Foundation
import NikoMusicCore



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
            return "Niko Music Hub will copy “\(songTitle)” to Project Vault and verify the copy. It will then permanently delete this song’s folder in Active Projects. Deleted files do not go to the Trash. You can later use Restore & Open to copy a verified generation back into Active Projects. Settings currently records that you protect the Archive with an independent backup."
        }
        if !independentBackupConfirmed {
            return "Niko Music Hub will copy “\(songTitle)” to Project Vault and verify the copy. Removing the Active Projects folder also requires the independent-backup setting. If that setting is off, the copy is kept and the Active folder stays. If that folder ever goes missing, Restore & Open brings it back."
        }
        return "Niko Music Hub will copy “\(songTitle)” to Project Vault and verify the copy. The Active Projects folder stays in place. If that folder ever goes missing, Restore & Open brings it back."
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

    /// Done storage choices. Done is a creative workflow state independent of
    /// storage: marking Done always commits the status, then handles the
    /// Active folder per choice. Removal is offered only when the bound token
    /// allows it.
    public static let workflowDoneFreeSpaceTitle = "Archive and free up space"
    public static let workflowDoneKeepCopyTitle = "Keep a verified copy"
    public static let workflowDoneKeepLocalTitle = "Keep on this Mac"

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
            return "Moving “\(songTitle)” to Done starts a Project Vault archive. After a verified copy, Niko Music Hub permanently deletes this song’s folder in Active Projects because you chose Archive and free up space and Settings records an independent backup. Deleted files do not go to the Trash. Recovery is Restore & Open."
        }
        return "Moving “\(songTitle)” to Done starts a Project Vault archive. The Active Projects folder stays in place. You can change the workflow status later from the card menu or with Edit → Undo."
    }

    public static func workflowDoneChoiceTitle(willRemoveActiveCopy: Bool) -> String {
        willRemoveActiveCopy ? "Move to Done?" : "Move to Done?"
    }

    /// Concise choice message for the three-option Done confirmation. States
    /// the Done commit plus the storage outcome without implying scheduler
    /// behavior. Removal wording restates the backup gate; copy/local wording
    /// states the Active folder stays.
    public static func workflowDoneChoiceMessage(
        songTitle: String,
        willRemoveActiveCopy: Bool
    ) -> String {
        if willRemoveActiveCopy {
            return "“\(songTitle)” will be marked Done. Archive and free up space verifies a Vault copy, then permanently deletes the Active folder. Deleted files do not go to the Trash. Settings records an independent backup. Recovery is Restore & Open."
        }
        return "“\(songTitle)” will be marked Done and the Active folder stays. You can still keep a verified copy, or keep it on this Mac. Change status later with Edit → Undo."
    }

    public static let independentBackupToggleTitle = "I protect the Archive with an independent backup"

    public static let independentBackupToggleFooter =
        "Archive Now can delete the Active Projects folder only when this is on and the other safety checks pass. Turning this on does not delete anything. Niko Music Hub still asks before Archive Now."

    public static let vaultEnabledSuccessMessage =
        "Project Vault is on. New archives keep a verified copy. Archive and free up space removes the Active copy only after you confirm, and only when independent backup is recorded and the other safety checks pass."

    /// Automatic-Done destructive-consent contract (V3). Marking a project
    /// Done without a bound per-operation authorization only ever creates a
    /// verified copy: neither the Done status, a relaunch, nor permissive
    /// settings imply approval to remove the Active copy. Removal requires an
    /// explicit Archive confirmation captured for that operation; undoing Done
    /// revokes the queued automation instead of deleting.
    public static let automaticDoneCopyOnlyContract =
        "Marking Done without an explicit Archive confirmation creates a verified copy only. The Active copy stays until you confirm its removal, and undoing Done revokes the queued archive."

    /// Archive Now notice while a Keep Local review is pending. Removal is
    /// paused because pins may be missing; the dialog offers a verified copy
    /// only, never the removal prompt.
    public static let keepLocalReviewRequiredArchiveNowMessage =
        "Keep Local needs review in Settings > Project Vault: pins may be missing, so removal is paused. You can still archive a verified copy."

    /// Settings notice explaining the repair reset. Plain words, no type names.
    public static let keepLocalReviewRequiredSettingsNotice =
        "A settings repair reset the Keep Local list. Some projects may no longer be pinned, so removing Active copies is paused until you review."

    /// Review sheet body. Only readable pins survived the repair;
    /// unreadable entries could not be listed, and the raw settings backup
    /// was saved. Never list opaque IDs as titles or invent dropped names;
    /// the sheet shows only the surviving pin count and routes to Archive
    /// Browser for title-based inspection and re-pinning.
    public static let keepLocalReviewSheetMessage =
        "A settings repair reset the Keep Local list. Only readable pins were kept; unreadable entries could not be shown. The original settings were saved to a backup. Removal stays paused until you finish reviewing."

    public static let keepLocalReviewSheetConfirmLabel =
        "I checked projects in Archive Browser for missing pins"

    /// Navigation hint inside the review sheet. Points at the existing
    /// Archive Browser detail-view Keep Local toggle and explains the return
    /// path; the sheet never embeds its own project browser. Projects are
    /// inspected by title; opaque IDs are never shown as titles.
    public static let keepLocalReviewSheetBrowserHint =
        "Open Archive Browser, find projects by title, and turn on Keep Local in its detail view. Then return to Settings > Project Vault and finish this review."

    public static let keepLocalReviewOpenBrowserLabel = "Open Archive Browser…"

    /// Setup precondition inside the review sheet. Review cannot finish while
    /// Vault is off or its roots are missing: the durable pause stays until
    /// the user picks both folders, enables Vault, revisits Archive Browser,
    /// and checks the box. Leaving Vault off changes no project files.
    public static let keepLocalReviewSheetVaultSetupHint =
        "Choose Active and Archive folders and turn on Project Vault before finishing review. Leaving Vault off keeps removal paused; no project files change."

    /// State line shown when Vault setup is still missing. Mirrors the
    /// browser-visit line: Done Reviewing stays disabled until both read.
    public static let keepLocalReviewSheetVaultSetupRequiredLine =
        "Project Vault setup is required before Done Reviewing."

    /// Review-complete notice. States the review is done while restating
    /// that Emergency Stop, After archiving, backup, and the normal safety
    /// gates still apply. It never implies removal is now available.
    public static let keepLocalReviewClearedMessage =
        "Keep Local review complete. Emergency Stop, After archiving, backup, and safety checks still apply."
}

/// Done Reviewing clears only the durable review flag against the latest
/// stored settings. It never writes the pin set, so a pin added while the
/// review sheet is open survives the save (no view-snapshot overwrite).
/// Clearance requires all four at once: a pending review obligation, an
/// explicit confirmation, a recorded Archive Browser visit, and a configured
/// Vault (enabled, with both selected root IDs present as enabled
/// StoredMusicRoot entries of the matching roles). A visit recorded before a
/// root change authorizes nothing: the guard runs on the latest settings
/// inside the save closure, so an empty or re-pointed Vault cannot be
/// reviewed away. The checkbox alone never suffices. The visit is short-lived
/// view state (reset on a fresh repair obligation and on any Vault
/// enablement/root change while review is pending); this policy is the
/// testable guard used by the save path so a disabled button is not the only
/// enforcement.
public enum KeepLocalReviewPolicy: Sendable {
    /// Vault is reviewable only when it is enabled and both selected roots
    /// resolve to enabled stored roots of the matching roles. Vault off,
    /// missing IDs, unknown IDs, role mismatches, and disabled roots all
    /// refuse.
    public static func vaultRootsConfigured(in settings: AppSettings) -> Bool {
        guard settings.vault.isEnabled else { return false }
        guard let activeID = settings.vault.activeRootID,
              let archiveID = settings.vault.archiveRootID
        else { return false }
        guard let active = settings.musicRoots.first(where: { $0.id == activeID }),
              let archive = settings.musicRoots.first(where: { $0.id == archiveID })
        else { return false }
        guard active.role == .active, archive.role == .archive else { return false }
        guard active.isEnabled, archive.isEnabled else { return false }
        return true
    }

    public static func canCompleteReview(
        _ settings: AppSettings,
        confirmed: Bool,
        browserVisited: Bool
    ) -> Bool {
        guard settings.vault.keepLocalReviewRequired else { return false }
        guard confirmed, browserVisited else { return false }
        return vaultRootsConfigured(in: settings)
    }

    @discardableResult
    public static func completeReview(
        _ settings: inout AppSettings,
        confirmed: Bool,
        browserVisited: Bool
    ) -> Bool {
        guard canCompleteReview(settings, confirmed: confirmed, browserVisited: browserVisited) else {
            return false
        }
        settings.vault.keepLocalReviewRequired = false
        return true
    }
}
