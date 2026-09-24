import Foundation
import NikoMusicCore

public enum ProjectVaultLocationState: String, Codable, CaseIterable, Sendable {
    case active = "Active"
    case archived = "Archived"
    case restoring = "Restoring"
    case archiving = "Archiving"
    case keepLocal = "Keep Local"
    case needsAttention = "Needs Attention"
}

public enum ProjectVaultPrimaryAction: Equatable, Sendable {
    case openInCubase
    case restoreAndOpen
    case revealArchive
    case retry
    case review
    /// A verified archive generation exists and the local Active copy is still
    /// retained. This action never deletes: it routes through the existing
    /// bound manual archive capture for an explicit fresh confirmation, which
    /// rechecks every live gate (master enablement, pause, Keep Local,
    /// independent backup) at capture and again at execution.
    case freeUpSpace

    public var label: String {
        switch self {
        case .openInCubase: "Open project"
        case .restoreAndOpen: "Restore & Open"
        case .revealArchive: "Show in Finder"
        case .retry: "Retry"
        case .review: "Review"
        case .freeUpSpace: "Free Up Space"
        }
    }
}

public enum ProjectVaultReviewAction: Equatable, Sendable {
    case makeAvailableOfflineInFinder(generationURL: URL)

    public var label: String {
        switch self {
        case .makeAvailableOfflineInFinder: "Make Available Offline in Finder"
        }
    }
}

/// Resolves only the currently configured Project Vault generation namespace.
/// Persisted transfer paths and Song locations are evidence, never authority.
public struct ProjectVaultGenerationReviewResolver: Equatable, Sendable {
    public let archiveRootURL: URL

    public init?(
        settings: AppSettings,
        bookmarkResolver: any SecurityScopedBookmarkResolving = FoundationSecurityScopedBookmarks()
    ) {
        guard settings.vault.isEnabled,
              let archiveRootID = settings.vault.archiveRootID,
              let storedRoot = settings.musicRoots.first(where: {
                  $0.id == archiveRootID && $0.role == .archive && $0.isEnabled
              }),
              let resolved = try? storedRoot.resolvedURL(using: bookmarkResolver) else {
            return nil
        }
        self.init(archiveRootURL: resolved)
    }

    public init?(archiveRootURL: URL) {
        let canonical = archiveRootURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        self.archiveRootURL = canonical
    }

    public func resolveGeneration(_ generationURL: URL) -> URL? {
        let generationsRoot = archiveRootURL
            .appendingPathComponent("generations", isDirectory: true)
            .standardizedFileURL
        let candidate = generationURL.standardizedFileURL
        let safety = PathSafety()
        guard safety.isResolvedContainedWithoutNestedSymlinks(generationsRoot, in: archiveRootURL),
              safety.isResolvedContainedWithoutNestedSymlinks(candidate, in: generationsRoot),
              candidate != generationsRoot else {
            return nil
        }
        let rootComponents = generationsRoot.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count >= rootComponents.count + 2,
              Array(candidateComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return candidate.resolvingSymlinksInPath().standardizedFileURL
    }

    public func isBoundGenerationPath(
        _ generationURL: URL,
        projectID: ProjectID,
        transferID: UUID
    ) -> Bool {
        guard generationURL.isFileURL,
              archiveRootURL.isFileURL,
              (generationURL.host ?? "").isEmpty,
              (archiveRootURL.host ?? "").isEmpty else {
            return false
        }

        let candidate = generationURL.standardizedFileURL
        let expected = archiveRootURL
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent(
                "generation-\(transferID.uuidString.lowercased())",
                isDirectory: true
            )
            .standardizedFileURL
        guard candidate.path == expected.path else {
            return false
        }

        return PathSafety().isResolvedContainedWithoutNestedSymlinks(candidate, in: archiveRootURL)
    }

    public func resolveGeneration(
        _ generationURL: URL,
        projectID: ProjectID,
        transferID: UUID
    ) -> URL? {
        guard isBoundGenerationPath(
            generationURL,
            projectID: projectID,
            transferID: transferID
        ) else {
            return nil
        }

        let candidate = generationURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              PathSafety().isResolvedContainedWithoutNestedSymlinks(candidate, in: archiveRootURL) else {
            return nil
        }
        return candidate
    }
}

public struct ProjectVaultCardPresentation: Equatable, Sendable {
    public let availability: Availability?
    public let restorePhase: VaultRestorePhase?
    /// The transfer phase behind an in-progress card, retained so the status
    /// line can name the actual phase (Queued, Copying, Verifying, Waiting for
    /// upload) instead of advertising completion before the actual state.
    public let transferState: VaultTransferState?
    /// Persisted-evidence readiness: a verified terminal generation plus a
    /// retained local Active copy with no Keep Local pin, offered only when
    /// the live free-space gates already pass. Never authority to delete.
    public let isReadyToFreeSpace: Bool
    /// Copy-only verified generation with the Active copy retained, shown when
    /// the free-space offer does not apply. Archive verification is reported
    /// separately from workflow status; the project stays visible and nothing
    /// is removed automatically.
    public let isVerifiedCopy: Bool

    public var statusLabel: String {
        if isReadyToFreeSpace, state == .active {
            return "Ready to free space"
        }
        if isVerifiedCopy, state == .active {
            return "Verified copy"
        }
        if state == .archiving, let transferState {
            return Self.transferStatusLabel(transferState)
        }
        guard state == .archived || state == .active || state == .keepLocal || state == .needsAttention else {
            return state.rawValue
        }
        guard let availability else {
            return state == .needsAttention ? "Needs attention" : state.rawValue
        }
        let label: String = switch availability {
        case .local: "Local"
        case .onlineOnly: "Online-only"
        case .materializing: "Downloading"
        case .missing: "Unavailable"
        }
        return state == .archived ? "Archived · \(label)" : (state == .needsAttention ? "Needs attention · \(label)" : state.rawValue)
    }

    /// User-facing transfer-phase wording. A provider wait is never shown as
    /// archived, a verified terminal generation is never shown as still
    /// archiving, and a verified copy with the Active folder retained is never
    /// shown as done: it is "Ready to free space" pending a fresh
    /// confirmation, or "Verified copy" when no free-space offer applies.
    public static func transferStatusLabel(_ state: VaultTransferState) -> String {
        switch state {
        case .archiveEligible, .preparingArchive:
            return "Queued"
        case .copyingToArchiveStaging:
            return "Copying"
        case .verifyingArchiveStaging:
            return "Verifying"
        case .awaitingProviderDurability, .promotingArchiveGeneration:
            return "Waiting for upload"
        case .archiveVerified, .archivedLocal, .archivedOnlineOnly:
            return "Verified"
        default:
            return "Archiving"
        }
    }

    public var retryRestoreLabel: String {
        restorePhase == .openingInCubase ? "Retry Open" : "Retry Restore"
    }

    public var primaryActionLabel: String {
        retryRestoreID == nil ? primaryAction.label : retryRestoreLabel
    }

    public let state: ProjectVaultLocationState
    public let primaryAction: ProjectVaultPrimaryAction
    public let explanation: String
    public let isKeepLocal: Bool
    public let reviewAction: ProjectVaultReviewAction?
    public let retryRestoreID: UUID?

    public init(
        record: ProjectRecord,
        transferState: VaultTransferState? = nil,
        transferErrorOrigin: VaultTransferState? = nil,
        restorePhase: VaultRestorePhase? = nil,
        restore: VaultRestoreRecord? = nil,
        linkedArchiveAvailability: Availability? = nil,
        isReadyToFreeSpace: Bool = false,
        isVerifiedCopy: Bool = false
    ) {
        self.transferState = transferState
        self.isReadyToFreeSpace = isReadyToFreeSpace
        self.isVerifiedCopy = isVerifiedCopy
        isKeepLocal = record.pinned
        self.restorePhase = restore?.phase ?? restorePhase
        availability = record.locations.contains { $0.kind == .active && $0.availability == .local }
            ? .local
            : linkedArchiveAvailability ?? record.locations.first { $0.kind == .archive && $0.availability != .missing }?.availability
                ?? record.locations.first { $0.kind == .archive }?.availability
        if restore?.failureReason == .activeDestinationIntegrityMismatch {
            reviewAction = nil
            retryRestoreID = nil
            state = .needsAttention
            primaryAction = .review
            explanation = "The restored files changed after they were verified, so the project won’t open. Every copy was kept for you to check."
            return
        }
        if restore?.phase == .superseded || restore?.supersededBy != nil {
            reviewAction = nil
            retryRestoreID = nil
            state = .needsAttention
            primaryAction = .review
            explanation = ProjectVaultActivityExplanation.restore(.superseded)
            return
        }
        if restore?.failureReason == .archiveGenerationIntegrityMismatch {
            reviewAction = nil
            retryRestoreID = nil
            state = .needsAttention
            primaryAction = .review
            explanation = restore?.error ?? "Files in the Vault copy changed since it was verified. Check them before restoring. Every copy was kept."
            return
        }
        if let restore, restore.completedAt == nil, restore.error != nil,
           restore.failureReason == nil,
           restore.phase != .superseded {
            reviewAction = nil
            retryRestoreID = restore.id
            state = .needsAttention
            primaryAction = .review
            switch restore.phase {
            case .materializingArchive:
                explanation = "The Vault copy couldn’t finish downloading. Check the drive or your cloud connection, then choose Retry Restore. Every copy was kept."
            case .copyingToActiveStaging:
                explanation = "Copying stopped. Check free space and access to Active Projects, then choose Retry Restore. The Vault copy and the partial copy were kept."
            case .verifyingActiveStaging:
                explanation = "The copied files couldn’t be verified, so the project wasn’t opened. The Vault copy and the copied files were kept. Make sure the Vault is available, then choose Retry Restore."
            case .promotingActiveCopy:
                explanation = "The verified copy couldn’t be moved into Active Projects. Check for a folder with the same name or a permissions problem, then choose Retry Restore. Nothing will be overwritten."
            case .persistingActiveLocation:
                explanation = "The project is restored, but the app couldn’t save where it lives. Check disk space and access, then choose Retry Restore. It will be verified again before opening."
            case .openingInCubase:
                explanation = "Restored and verified, but your DAW couldn’t open it. Check that Cubase or Ableton Live is installed, then choose Retry Open. The files will be verified again first."
            case .superseded:
                explanation = ProjectVaultActivityExplanation.restore(.superseded)
            }
            return
        }
        if let restore,
           restore.failureReason == .legacyProjectionEvidenceUnavailable,
           let generationURL = restore.reviewGenerationURL {
            reviewAction = .makeAvailableOfflineInFinder(generationURL: generationURL)
            retryRestoreID = restore.id
        } else {
            reviewAction = nil
            retryRestoreID = nil
        }
        let hasLocalActiveCopy = record.locations.contains {
            $0.kind == .active && $0.availability == .local
        }
        if restore?.failureReason == .archiveTransferBindingUnavailable {
            state = .needsAttention
            primaryAction = .review
            explanation = "This restore doesn’t match the verified Vault copy it was tied to, so it stopped. Every copy was kept. Check that Vault copy before trying again."
        } else if restore?.failureReason == .legacyProjectionIdentityMismatch {
            state = .needsAttention
            primaryAction = .review
            explanation = "This older Vault copy changed since it was verified, so it can’t be restored as is. Every copy was kept. Check its files in the Vault before retrying."
        } else if reviewAction != nil {
            state = .needsAttention
            primaryAction = .review
            explanation = "This older Vault copy has to be downloaded before its size can be checked. Use Make Available Offline in Finder, then retry. Nothing has been copied yet."
        } else if let effectiveRestorePhase = restore?.phase ?? restorePhase {
            state = .restoring
            primaryAction = .review
            explanation = ProjectVaultActivityExplanation.restore(effectiveRestorePhase)
        } else if transferState == .failedRecoverable {
            state = .needsAttention
            if let transferErrorOrigin,
               VaultTransferRetryPolicy.permitsNondestructiveArchiveOrigin(transferErrorOrigin) {
                primaryAction = .retry
                explanation = ProjectVaultActivityExplanation.transfer(.failedRecoverable)
            } else {
                primaryAction = .review
                explanation = "This paused step may already have removed files, so it won’t retry on its own. Whatever is left was kept for you to check."
            }
        } else if transferState == .recoveryRequired {
            state = .needsAttention
            primaryAction = .review
            switch transferErrorOrigin {
            case .removingActiveCopy:
                explanation = "Removing the Active folder was interrupted, so some or all of it may still be there. The Vault copy is still verified, and removal won’t restart on its own."
            case .evictingProviderCache:
                explanation = "The Active folder was removed, but clearing the cloud app’s offline copy was interrupted. The Vault copy is still verified, and this won’t restart on its own."
            default:
                explanation = ProjectVaultActivityExplanation.transfer(.recoveryRequired)
            }
        } else if let transferState, Self.archivingStates.contains(transferState) {
            state = .archiving
            primaryAction = .review
            explanation = ProjectVaultActivityExplanation.transfer(transferState)
        } else if isReadyToFreeSpace, !record.pinned, hasLocalActiveCopy {
            // Persistent, evidence-backed offer: a verified generation exists
            // and the Active copy is still retained. The status names the
            // pending choice without claiming it is authorized, and the action
            // is an explicit fresh confirmation, never a reused approval.
            state = .active
            primaryAction = .freeUpSpace
            explanation = "A verified copy is in the Vault, and the folder is still on this Mac. Nothing is removed until you confirm Free Up Space."
        } else if record.pinned, hasLocalActiveCopy {
            state = .keepLocal
            primaryAction = .openInCubase
            explanation = "Kept on this Mac. Automatic archiving skips it."
        } else if isVerifiedCopy, !record.pinned, hasLocalActiveCopy {
            // Copy-only verified generation with the Active folder retained.
            // Verification is reported separately from workflow status; the
            // project stays visible and directly openable, and nothing is
            // removed automatically.
            state = .active
            primaryAction = .openInCubase
            explanation = "A verified copy is in the Vault, and the folder is still on this Mac. Nothing is removed automatically."
        } else if hasLocalActiveCopy {
            state = .active
            primaryAction = .openInCubase
            explanation = "Ready in Active Projects."
        } else if let availability = linkedArchiveAvailability, availability != .missing {
            state = .archived
            primaryAction = .restoreAndOpen
            explanation = "Restore & Open downloads anything stored only in the cloud, copies it back to Active Projects, verifies it, and opens it. The Vault copy stays as it is."
        } else if record.locations.contains(where: { $0.kind == .archive && $0.availability != .missing }) {
            state = .archived
            primaryAction = .restoreAndOpen
            explanation = "Restore & Open copies this song back to Active Projects, verifies it, and opens the newest version. The Vault copy stays as it is."
        } else {
            state = .needsAttention
            primaryAction = .review
            explanation = "This project’s files can’t be found right now. Nothing will be changed."
        }
    }

    private static let archivingStates: Set<VaultTransferState> = [
        .archiveEligible, .preparingArchive, .copyingToArchiveStaging,
        .verifyingArchiveStaging, .awaitingProviderDurability,
        .promotingArchiveGeneration, .removingActiveCopy,
        .evictingProviderCache
    ]
}

public enum ProjectVaultActivityExplanation {
    public static func transfer(_ state: VaultTransferState) -> String {
        switch state {
        case .copyingToArchiveStaging: return "Copying to a temporary folder in the Vault. Your Active folder isn’t touched."
        case .verifyingArchiveStaging: return "Verifying every copied file."
        case .awaitingProviderDurability, .promotingArchiveGeneration: return "Waiting for cloud upload to finish. Your Active folder stays on this Mac."
        case .removingActiveCopy: return "Vault copy verified. Removing only the old Active folder."
        case .failedRecoverable: return "Paused safely. Every copy was kept, and you can retry."
        case .recoveryRequired: return "Needs your decision. Every copy we know about was kept."
        case .archivedOnlineOnly: return "Archived and synced. The cloud app’s offline copy on this Mac was cleared to free space."
        case .archivedLocal: return "Archived and verified. The cloud app couldn’t clear its offline copy safely, so it’s still on this Mac."
        default:
            let readableState = state.rawValue.replacingOccurrences(of: "_", with: " ")
            return "Project Vault is completing \(readableState)."
        }
    }

    public static func restore(_ phase: VaultRestorePhase) -> String {
        switch phase {
        case .materializingArchive: return "Downloading the Vault copy."
        case .copyingToActiveStaging: return "Copying to a temporary folder first. The Vault copy isn’t touched."
        case .verifyingActiveStaging: return "Verifying the restored files."
        case .promotingActiveCopy: return "Moving the verified copy into Active Projects."
        case .persistingActiveLocation: return "Saving where the project now lives."
        case .openingInCubase: return "Restored and verified. Opening it in your DAW."
        case .superseded: return "Another restore is already handling this project."
        }
    }
}

public enum ProjectVaultRolloutPolicy {
    /// Legacy scheduler gate, preserved for compatibility (diagnostics,
    /// out-of-scope capture pre-selection). Background inactivity/disk-pressure
    /// scheduling remains opt-in via `automaticArchiving`.
    public static func permitsAutomaticArchiving(_ settings: VaultSettings) -> Bool {
        settings.isEnabled
            && settings.automaticArchiving
            && !settings.automationEmergencyStop
            && settings.rolloutStage != .disabled
            && settings.activeRootID != nil
            && settings.archiveRootID != nil
    }

    /// User-initiated archiving (manual Archive Now, user-confirmed Done).
    /// Decoupled from the background scheduler opt-in: a Done confirmation
    /// copies even when `automaticArchiving` is off. The disabled rollout
    /// still blocks, so upgrades never gain new file operations from the
    /// migration itself.
    public static func permitsUserInitiatedArchiving(_ settings: VaultSettings) -> Bool {
        settings.isEnabled
            && !settings.automationEmergencyStop
            && settings.rolloutStage != .disabled
            && settings.activeRootID != nil
            && settings.archiveRootID != nil
    }

    /// Whether the stored settings express a free-space desire. The persisted
    /// `spaceIntent` is authoritative; legacy payloads without an intent key
    /// migrate at decode, so the rollout is never consulted here. An explicit
    /// `keepCopy` never authorizes removal, even alongside `friends`. The
    /// backup acknowledgement is a separate execution gate, never implied here.
    public static func expressesFreeSpaceIntent(_ settings: VaultSettings) -> Bool {
        settings.spaceIntent == .freeSpace
    }

    /// Scheduler-coupled removal gate. Honors the persisted free-space intent
    /// (legacy payloads without an intent key migrate at decode, so upgraded
    /// `friends` installs keep working while explicit `keepCopy` stays
    /// copy-only). Still scheduler-coupled; the runtime uses
    /// `permitsUserInitiatedRemoval` for Done so Done no longer waits on the
    /// scheduler opt-in. A pending Keep Local review denies removal even when
    /// every other gate passes; copy-only scheduling is unaffected.
    public static func permitsActiveCopyRemoval(_ settings: VaultSettings) -> Bool {
        !settings.keepLocalReviewRequired
            && permitsAutomaticArchiving(settings)
            && expressesFreeSpaceIntent(settings)
            && settings.independentBackupConfirmed
    }

    /// Done/manual removal gate used by the owned runtime admission. Composes
    /// the user-initiated archiving base — so a disabled rollout cannot
    /// bypass the capture gate — plus an explicit free-space intent and the
    /// backup acknowledgement, but not the background scheduler opt-in.
    /// Keep Local is per-song and enforced at capture/execution. A pending
    /// Keep Local review denies removal even with Emergency Stop cleared;
    /// only Review Keep Local in Settings clears it. Copy-only offers are
    /// unaffected.
    public static func permitsUserInitiatedRemoval(_ settings: VaultSettings) -> Bool {
        !settings.keepLocalReviewRequired
            && permitsUserInitiatedArchiving(settings)
            && expressesFreeSpaceIntent(settings)
            && settings.independentBackupConfirmed
    }
}
