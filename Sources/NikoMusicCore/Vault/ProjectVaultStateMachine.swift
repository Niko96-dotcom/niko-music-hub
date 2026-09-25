import Foundation

/// Durable phases for one archive or restore operation.
///
/// The model deliberately contains no generic `delete` transition. The only
/// removal phase is gated by evidence that the archive is durable and the
/// corresponding metadata has already been persisted.
public enum VaultTransferState: String, CaseIterable, Codable, Hashable, Sendable {
    case activeLocal
    case archiveEligible
    case preparingArchive
    case copyingToArchiveStaging
    case verifyingArchiveStaging
    case awaitingProviderDurability
    case promotingArchiveGeneration
    case archiveVerified
    case removingActiveCopy
    case evictingProviderCache
    case archivedOnlineOnly
    case archivedLocal
    case materializingArchive
    case copyingToActiveStaging
    case verifyingActiveStaging
    case promotingActiveCopy
    case readyLocal
    case openingInCubase
    case failedRecoverable
    case recoveryRequired
    case superseded
}
public enum VaultDurability: String, Codable, Hashable, Sendable {
    case verifiedLocal
    case syncedToProvider
    case independentlyBackedUp
}

public struct VaultRemovalEvidence: Codable, Equatable, Sendable {
    public let manifestVerified: Bool
    public let archiveDurability: VaultDurability
    public let metadataPersisted: Bool

    public init(
        manifestVerified: Bool,
        archiveDurability: VaultDurability,
        metadataPersisted: Bool
    ) {
        self.manifestVerified = manifestVerified
        self.archiveDurability = archiveDurability
        self.metadataPersisted = metadataPersisted
    }

    public var permitsActiveCopyRemoval: Bool {
        manifestVerified && metadataPersisted
            && (archiveDurability == .verifiedLocal || archiveDurability == .syncedToProvider)
    }
}

public enum VaultTransition: Equatable, Sendable {
    case advance(to: VaultTransferState)
    case beginRemovingActiveCopy(VaultRemovalEvidence)
    case fail(VaultFailure)
}

public enum VaultTransitionError: Error, Equatable, Sendable {
    case illegal(from: VaultTransferState, to: VaultTransferState)
    case removalNotProven
    case failureOriginMismatch(expected: VaultTransferState, actual: VaultTransferState)
}

public struct VaultFailure: Codable, Equatable, Sendable {
    public let origin: VaultTransferState
    public let reason: VaultFailureReason
    public let requiresUserDecision: Bool

    public init(
        origin: VaultTransferState,
        reason: VaultFailureReason,
        requiresUserDecision: Bool = false
    ) {
        self.origin = origin
        self.reason = reason
        self.requiresUserDecision = requiresUserDecision
    }

    public var failureState: VaultTransferState {
        requiresUserDecision ? .recoveryRequired : .failedRecoverable
    }

    public var recoveryDecision: VaultRecoveryDecision {
        switch reason {
        case .slowProviderSync:
            .waitForProviderDurability(resumeAt: origin)
        case .providerOffline:
            .waitForConnectivity(resumeAt: origin)
        case .providerUnsynced:
            .waitForProviderDurability(resumeAt: origin)
        case .evictionUnsupported:
            .keepArchiveLocal
        case .permissionLost:
            .requestPermission(resumeAt: origin)
        case .sourceMutated:
            .discardStagingAndRestart
        case .integrityMismatch:
            .discardStagingAndRetry(resumeAt: origin)
        case .occupiedDestination:
            .requestAlternateDestination
        case .insufficientSpace:
            .freeSpaceAndRetry(resumeAt: origin)
        case .unknown:
            .manualReviewKeepingAllCopies
        }
    }
}

public enum VaultFailureReason: String, CaseIterable, Codable, Hashable, Sendable {
    case slowProviderSync
    case providerOffline
    case providerUnsynced
    case evictionUnsupported
    case permissionLost
    case sourceMutated
    case integrityMismatch
    case occupiedDestination
    case insufficientSpace
    case unknown
}

public enum VaultRecoveryDecision: Equatable, Sendable {
    case waitForProviderDurability(resumeAt: VaultTransferState)
    case waitForConnectivity(resumeAt: VaultTransferState)
    case keepArchiveLocal
    case requestPermission(resumeAt: VaultTransferState)
    case discardStagingAndRestart
    case discardStagingAndRetry(resumeAt: VaultTransferState)
    case requestAlternateDestination
    case freeSpaceAndRetry(resumeAt: VaultTransferState)
    case manualReviewKeepingAllCopies
}

public struct ProjectVaultStateMachine: Sendable {
    public init() {}

    public func applying(
        _ transition: VaultTransition,
        to state: VaultTransferState
    ) throws -> VaultTransferState {
        switch transition {
        case let .advance(destination):
            guard Self.allowedDestinations[state, default: []].contains(destination) else {
                throw VaultTransitionError.illegal(from: state, to: destination)
            }
            return destination

        case let .beginRemovingActiveCopy(evidence):
            guard state == .archiveVerified else {
                throw VaultTransitionError.illegal(from: state, to: .removingActiveCopy)
            }
            guard evidence.permitsActiveCopyRemoval else {
                throw VaultTransitionError.removalNotProven
            }
            return .removingActiveCopy

        case let .fail(failure):
            guard failure.origin == state else {
                throw VaultTransitionError.failureOriginMismatch(
                    expected: state,
                    actual: failure.origin
                )
            }
            return failure.failureState
        }
    }

    public func allowedDestinations(from state: VaultTransferState) -> Set<VaultTransferState> {
        Self.allowedDestinations[state, default: []]
    }

    private static let allowedDestinations: [VaultTransferState: Set<VaultTransferState>] = [
        .activeLocal: [.archiveEligible],
        .archiveEligible: [.preparingArchive],
        .preparingArchive: [.copyingToArchiveStaging],
        .copyingToArchiveStaging: [.verifyingArchiveStaging],
        .verifyingArchiveStaging: [.awaitingProviderDurability],
        .awaitingProviderDurability: [.promotingArchiveGeneration],
        .promotingArchiveGeneration: [.archiveVerified],
        .archiveVerified: [], // removal uses the evidence-gated transition above
        .removingActiveCopy: [.evictingProviderCache],
        .evictingProviderCache: [.archivedOnlineOnly, .archivedLocal],
        .archivedOnlineOnly: [.materializingArchive],
        .archivedLocal: [.materializingArchive],
        .materializingArchive: [.copyingToActiveStaging],
        .copyingToActiveStaging: [.verifyingActiveStaging],
        .verifyingActiveStaging: [.promotingActiveCopy],
        .promotingActiveCopy: [.readyLocal],
        .readyLocal: [.openingInCubase],
        .openingInCubase: [],
        .failedRecoverable: [],
        .recoveryRequired: [],
        .superseded: []
    ]
}
