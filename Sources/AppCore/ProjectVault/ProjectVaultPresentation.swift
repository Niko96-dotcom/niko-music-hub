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
    case retry
    case review

    public var label: String {
        switch self {
        case .openInCubase: "Open project"
        case .restoreAndOpen: "Get Local & Open"
        case .retry: "Retry"
        case .review: "Review"
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
        restore: VaultRestoreRecord? = nil
    ) {
        isKeepLocal = record.pinned
        if restore?.failureReason == .activeDestinationIntegrityMismatch {
            reviewAction = nil
            retryRestoreID = nil
            state = .needsAttention
            primaryAction = .review
            explanation = "The restored Active copy no longer matches the verified archive manifest. It will not be opened; existing copies were kept for review."
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
            explanation = restore?.error ?? "The archive no longer matches its verified manifest. Review the changed files before restoring. Existing copies were kept."
            return
        }
        if let restore, restore.completedAt == nil, restore.error != nil,
           restore.failureReason == nil,
           [.materializingArchive, .copyingToActiveStaging, .verifyingActiveStaging].contains(restore.phase) {
            reviewAction = nil
            retryRestoreID = restore.id
            state = .needsAttention
            primaryAction = .review
            explanation = "Restore stopped before completion. Existing copies were kept. Check archive availability and integrity, then choose Retry Get Local to verify and resume this restore."
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
            explanation = "This restore no longer matches its verified archive transfer binding. Existing copies were kept; review archive integrity before continuing."
        } else if restore?.failureReason == .legacyProjectionIdentityMismatch {
            state = .needsAttention
            primaryAction = .review
            explanation = "This legacy archive no longer matches its verified content identity. Existing copies were kept; reconcile the exact generation before retrying."
        } else if reviewAction != nil {
            state = .needsAttention
            primaryAction = .review
            explanation = "This legacy archive needs fresh capacity evidence. Make the exact generation available offline in Finder, then retry this restore. No archive bytes were downloaded or copied."
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
                explanation = "This paused operation cannot be retried automatically because it may remove or evict files. Existing copies were kept for review."
            }
        } else if transferState == .recoveryRequired {
            state = .needsAttention
            primaryAction = .review
            switch transferErrorOrigin {
            case .removingActiveCopy:
                explanation = "Archive generation remains verified. Active-copy removal was interrupted, so the Active copy may or may not remain; automatic removal will not resume."
            case .evictingProviderCache:
                explanation = "Archive generation remains verified. Active-copy removal completed, but provider-cache eviction was interrupted; automatic eviction will not resume."
            default:
                explanation = ProjectVaultActivityExplanation.transfer(.recoveryRequired)
            }
        } else if let transferState, Self.archivingStates.contains(transferState) {
            state = .archiving
            primaryAction = .review
            explanation = ProjectVaultActivityExplanation.transfer(transferState)
        } else if record.pinned, hasLocalActiveCopy {
            state = .keepLocal
            primaryAction = .openInCubase
            explanation = "Pinned here. Automatic archiving will leave this project in Active Projects."
        } else if hasLocalActiveCopy {
            state = .active
            primaryAction = .openInCubase
            explanation = "Ready in Active Projects."
        } else if record.locations.contains(where: { $0.kind == .archive && $0.availability != .missing }) {
            state = .archived
            primaryAction = .restoreAndOpen
            explanation = "Restore & Open copies this song into Active Projects, verifies the copy, then opens its newest project in the matching DAW. The archive stays intact."
        } else {
            state = .needsAttention
            primaryAction = .review
            explanation = "No safe, available project location could be confirmed. No files will be changed."
        }
    }

    private static let archivingStates: Set<VaultTransferState> = [
        .archiveEligible, .preparingArchive, .copyingToArchiveStaging,
        .verifyingArchiveStaging, .awaitingProviderDurability,
        .promotingArchiveGeneration, .archiveVerified, .removingActiveCopy,
        .evictingProviderCache
    ]
}

public enum ProjectVaultActivityExplanation {
    public static func transfer(_ state: VaultTransferState) -> String {
        switch state {
        case .copyingToArchiveStaging: return "Copying into a private staging folder. The Active copy is untouched."
        case .verifyingArchiveStaging: return "Verifying every staged file before publishing the archive generation."
        case .awaitingProviderDurability: return "Waiting for the archive provider to confirm sync. The Active copy remains local."
        case .removingActiveCopy: return "Archive durability and metadata are verified; removing only the superseded Active copy."
        case .failedRecoverable: return "Work paused safely and can be retried. Existing copies were kept."
        case .recoveryRequired: return "A choice is required. Project Vault kept every known copy."
        case .archivedOnlineOnly: return "Archived and provider-synced; local provider cache was released."
        case .archivedLocal: return "Archived and verified locally. The provider could not safely release its local cache."
        default:
            let readableState = state.rawValue.replacingOccurrences(of: "_", with: " ")
            return "Project Vault is completing \(readableState)."
        }
    }

    public static func restore(_ phase: VaultRestorePhase) -> String {
        switch phase {
        case .materializingArchive: return "Downloading the verified archive generation."
        case .copyingToActiveStaging: return "Copying into Active Projects staging. The archive remains untouched."
        case .verifyingActiveStaging: return "Verifying the restored copy before it becomes active."
        case .promotingActiveCopy: return "Publishing the verified copy into Active Projects."
        case .persistingActiveLocation: return "Saving the restored location before opening the project."
        case .openingInCubase: return "Restore is verified. Opening the project in its DAW."
        case .superseded: return "A newer restore recovery job owns this project."
        }
    }
}

public enum ProjectVaultRolloutPolicy {
    public static func permitsAutomaticArchiving(_ settings: VaultSettings) -> Bool {
        settings.isEnabled
            && settings.automaticArchiving
            && !settings.automationEmergencyStop
            && settings.rolloutStage != .disabled
            && settings.activeRootID != nil
            && settings.archiveRootID != nil
    }

    public static func permitsActiveCopyRemoval(_ settings: VaultSettings) -> Bool {
        permitsAutomaticArchiving(settings)
            && settings.rolloutStage == .friends
            && settings.independentBackupConfirmed
    }
}
