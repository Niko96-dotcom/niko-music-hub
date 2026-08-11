import XCTest
@testable import NikoMusicCore

final class ProjectVaultStateMachineTests: XCTestCase {
    private let machine = ProjectVaultStateMachine()

    func testEveryNormalTransitionInFrozenArchiveAndRestoreGraph() throws {
        let transitions: [(VaultTransferState, VaultTransferState)] = [
            (.activeLocal, .archiveEligible),
            (.archiveEligible, .preparingArchive),
            (.preparingArchive, .copyingToArchiveStaging),
            (.copyingToArchiveStaging, .verifyingArchiveStaging),
            (.verifyingArchiveStaging, .awaitingProviderDurability),
            (.awaitingProviderDurability, .promotingArchiveGeneration),
            (.promotingArchiveGeneration, .archiveVerified),
            (.removingActiveCopy, .evictingProviderCache),
            (.evictingProviderCache, .archivedOnlineOnly),
            (.evictingProviderCache, .archivedLocal),
            (.archivedOnlineOnly, .materializingArchive),
            (.archivedLocal, .materializingArchive),
            (.materializingArchive, .copyingToActiveStaging),
            (.copyingToActiveStaging, .verifyingActiveStaging),
            (.verifyingActiveStaging, .promotingActiveCopy),
            (.promotingActiveCopy, .readyLocal),
            (.readyLocal, .openingInCubase)
        ]

        for (source, destination) in transitions {
            XCTAssertEqual(
                try machine.applying(.advance(to: destination), to: source),
                destination,
                "\(source) -> \(destination)"
            )
        }
    }

    func testAllStatesHaveExactlyTheFrozenOutgoingGraph() {
        let expected: [VaultTransferState: Set<VaultTransferState>] = [
            .activeLocal: [.archiveEligible],
            .archiveEligible: [.preparingArchive],
            .preparingArchive: [.copyingToArchiveStaging],
            .copyingToArchiveStaging: [.verifyingArchiveStaging],
            .verifyingArchiveStaging: [.awaitingProviderDurability],
            .awaitingProviderDurability: [.promotingArchiveGeneration],
            .promotingArchiveGeneration: [.archiveVerified],
            .archiveVerified: [],
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
        XCTAssertEqual(Set(expected.keys), Set(VaultTransferState.allCases))
        for state in VaultTransferState.allCases {
            XCTAssertEqual(machine.allowedDestinations(from: state), expected[state])
        }
    }

    func testActiveRemovalRequiresVerifiedManifestAndPersistedMetadata() throws {
        let valid = VaultRemovalEvidence(
            manifestVerified: true,
            archiveDurability: .syncedToProvider,
            metadataPersisted: true
        )
        XCTAssertEqual(
            try machine.applying(.beginRemovingActiveCopy(valid), to: .archiveVerified),
            .removingActiveCopy
        )

        for invalid in [
            VaultRemovalEvidence(manifestVerified: false, archiveDurability: .syncedToProvider, metadataPersisted: true),
            VaultRemovalEvidence(manifestVerified: true, archiveDurability: .syncedToProvider, metadataPersisted: false)
        ] {
            XCTAssertThrowsError(
                try machine.applying(.beginRemovingActiveCopy(invalid), to: .archiveVerified)
            ) { XCTAssertEqual($0 as? VaultTransitionError, .removalNotProven) }
        }
    }

    func testNoStateCanAdvanceDirectlyToDestructiveOrPromotionStates() {
        let guardedDestinations: Set<VaultTransferState> = [
            .removingActiveCopy, .promotingArchiveGeneration, .promotingActiveCopy
        ]
        for source in VaultTransferState.allCases {
            for destination in guardedDestinations where
                !machine.allowedDestinations(from: source).contains(destination)
            {
                XCTAssertThrowsError(
                    try machine.applying(.advance(to: destination), to: source),
                    "unexpected \(source) -> \(destination)"
                )
            }
        }
    }

    func testEveryFailureReasonHasAnExplicitFailClosedRecoveryDecision() throws {
        let expected: [VaultFailureReason: VaultRecoveryDecision] = [
            .slowProviderSync: .waitForProviderDurability(resumeAt: .awaitingProviderDurability),
            .providerOffline: .waitForConnectivity(resumeAt: .awaitingProviderDurability),
            .providerUnsynced: .waitForProviderDurability(resumeAt: .awaitingProviderDurability),
            .evictionUnsupported: .keepArchiveLocal,
            .permissionLost: .requestPermission(resumeAt: .awaitingProviderDurability),
            .sourceMutated: .discardStagingAndRestart,
            .integrityMismatch: .discardStagingAndRetry(resumeAt: .awaitingProviderDurability),
            .occupiedDestination: .requestAlternateDestination,
            .insufficientSpace: .freeSpaceAndRetry(resumeAt: .awaitingProviderDurability),
            .unknown: .manualReviewKeepingAllCopies
        ]
        XCTAssertEqual(Set(expected.keys), Set(VaultFailureReason.allCases))

        for reason in VaultFailureReason.allCases {
            let needsUser = reason == .occupiedDestination || reason == .unknown
            let failure = VaultFailure(
                origin: .awaitingProviderDurability,
                reason: reason,
                requiresUserDecision: needsUser
            )
            XCTAssertEqual(failure.recoveryDecision, expected[reason])
            XCTAssertEqual(
                try machine.applying(.fail(failure), to: .awaitingProviderDurability),
                needsUser ? .recoveryRequired : .failedRecoverable
            )
        }
    }

    func testFailureCannotBeAttachedToADifferentOrigin() {
        let failure = VaultFailure(origin: .copyingToArchiveStaging, reason: .permissionLost)
        XCTAssertThrowsError(try machine.applying(.fail(failure), to: .archiveVerified)) {
            XCTAssertEqual(
                $0 as? VaultTransitionError,
                .failureOriginMismatch(expected: .archiveVerified, actual: .copyingToArchiveStaging)
            )
        }
    }
}
