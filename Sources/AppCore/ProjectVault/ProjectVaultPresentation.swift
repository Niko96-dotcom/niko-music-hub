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
    case review

    public var label: String {
        switch self {
        case .openInCubase: "Open in Cubase"
        case .restoreAndOpen: "Restore & Open"
        case .review: "Review"
        }
    }
}

public struct ProjectVaultCardPresentation: Equatable, Sendable {
    public let state: ProjectVaultLocationState
    public let primaryAction: ProjectVaultPrimaryAction
    public let explanation: String

    public init(record: ProjectRecord, transferState: VaultTransferState? = nil, restorePhase: VaultRestorePhase? = nil) {
        if restorePhase != nil {
            state = .restoring
            primaryAction = .review
            explanation = ProjectVaultActivityExplanation.restore(restorePhase!)
        } else if let transferState, [.failedRecoverable, .recoveryRequired].contains(transferState) {
            state = .needsAttention
            primaryAction = .review
            explanation = ProjectVaultActivityExplanation.transfer(transferState)
        } else if let transferState, Self.archivingStates.contains(transferState) {
            state = .archiving
            primaryAction = .review
            explanation = ProjectVaultActivityExplanation.transfer(transferState)
        } else if record.pinned {
            state = .keepLocal
            primaryAction = .openInCubase
            explanation = "Pinned here. Automatic archiving will leave this project in Active Projects."
        } else if record.locations.contains(where: { $0.kind == .active && $0.availability == .local }) {
            state = .active
            primaryAction = .openInCubase
            explanation = "Ready in Active Projects."
        } else if record.locations.contains(where: { $0.kind == .archive && $0.availability != .missing }) {
            state = .archived
            primaryAction = .restoreAndOpen
            explanation = "A verified archive generation is available. Restore keeps that archive copy."
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
        case .persistingActiveLocation: return "Saving the restored location before Cubase opens."
        case .openingInCubase: return "Restore is verified. Opening the project in Cubase."
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
