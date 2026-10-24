import Foundation

/// Durable phases of one archive transfer, saved in `vault_transfers`. Restores
/// use `VaultRestorePhase`; no transfer record holds the restore-half cases
/// (`materializingArchive` … `openingInCubase`).
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
    /// Any change the table below lists: forward, a rewind, a stop or a retirement.
    case advance(to: VaultTransferState)
    case beginRemovingActiveCopy(VaultRemovalEvidence)
}

public enum VaultTransitionError: Error, Equatable, Sendable {
    case illegal(from: VaultTransferState, to: VaultTransferState)
    case removalNotProven
    case illegalRestorePhase(from: VaultRestorePhase, to: VaultRestorePhase)
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
        }
    }

    public func allowedDestinations(from state: VaultTransferState) -> Set<VaultTransferState> {
        Self.allowedDestinations[state, default: []]
    }

    /// Every state change `LocalVaultTransferEngine` makes, each with the path
    /// that makes it. A change the table does not list throws before anything is
    /// saved or any file is touched. Listed: each edge a path reaches through one
    /// event (one thrown error, one cancel, one launch or retry decision). Not
    /// listed: the restore-half states, which no transfer record ever held
    /// (restores use `VaultRestorePhase`), and the edges a path reaches only after
    /// a journal save already failed; the record then keeps its last saved state.
    private static let allowedDestinations: [VaultTransferState: Set<VaultTransferState>] = [
        // Archive chain. Each archive phase can also stop (`failedRecoverable`,
        // after a cancel or an error) and be retired at launch when a newer
        // verified generation of its project exists (`superseded`).
        .activeLocal: [.archiveEligible, .failedRecoverable, .superseded],
        .archiveEligible: [.preparingArchive, .failedRecoverable, .superseded],
        .preparingArchive: [.copyingToArchiveStaging, .failedRecoverable, .superseded],
        .copyingToArchiveStaging: [.verifyingArchiveStaging, .failedRecoverable, .superseded],
        .verifyingArchiveStaging: [.awaitingProviderDurability, .failedRecoverable, .superseded],
        .awaitingProviderDurability: [.promotingArchiveGeneration, .failedRecoverable, .superseded],
        // An occupied generation folder needs review (`recoveryRequired`).
        .promotingArchiveGeneration: [.archiveVerified, .failedRecoverable, .recoveryRequired, .superseded],
        // Removal re-proves the generation in place; entering removal takes the
        // evidence-gated transition above.
        .archiveVerified: [.archiveVerified],
        // Refused or stopped before `removeItem`: back to `archiveVerified`, the
        // Active folder kept. Stopped or failed at or after it, or found at
        // launch: `recoveryRequired`. A newer verified generation never retires
        // an interrupted removal; launch hands it to review instead.
        .removingActiveCopy: [.evictingProviderCache, .archiveVerified, .recoveryRequired],
        .evictingProviderCache: [.archivedOnlineOnly, .archivedLocal, .recoveryRequired],
        // A restored project's earlier generation: removal re-proves it.
        .archivedOnlineOnly: [.archiveVerified],
        .archivedLocal: [.archiveVerified],
        // Retry, at launch or by the person: back to the failed phase, or to a
        // fresh copy (portable retry). A legacy failure in a removal phase needs
        // review; a newer verified generation retires any other failure.
        .failedRecoverable: [
            .activeLocal, .archiveEligible, .preparingArchive, .copyingToArchiveStaging,
            .verifyingArchiveStaging, .awaitingProviderDurability, .promotingArchiveGeneration,
            .recoveryRequired, .superseded,
        ],
        // The person's recovery of an interrupted removal.
        .recoveryRequired: [.archiveVerified],
        .superseded: [],
        .materializingArchive: [],
        .copyingToActiveStaging: [],
        .verifyingActiveStaging: [],
        .promotingActiveCopy: [],
        .readyLocal: [],
        .openingInCubase: [],
    ]
}
