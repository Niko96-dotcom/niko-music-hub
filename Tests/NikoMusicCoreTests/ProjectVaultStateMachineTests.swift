import XCTest
@testable import NikoMusicCore

final class ProjectVaultStateMachineTests: XCTestCase {
    private let machine = ProjectVaultStateMachine()

    /// A frozen copy of the table: changing an edge means changing this test.
    func testAllStatesHaveExactlyTheFrozenOutgoingGraph() throws {
        let archivePhases: [VaultTransferState] = [
            .activeLocal, .archiveEligible, .preparingArchive, .copyingToArchiveStaging,
            .verifyingArchiveStaging, .awaitingProviderDurability, .promotingArchiveGeneration,
        ]
        let expected: [VaultTransferState: Set<VaultTransferState>] = [
            .activeLocal: [.archiveEligible, .failedRecoverable, .superseded],
            .archiveEligible: [.preparingArchive, .failedRecoverable, .superseded],
            .preparingArchive: [.copyingToArchiveStaging, .failedRecoverable, .superseded],
            .copyingToArchiveStaging: [.verifyingArchiveStaging, .failedRecoverable, .superseded],
            .verifyingArchiveStaging: [.awaitingProviderDurability, .failedRecoverable, .superseded],
            .awaitingProviderDurability: [.promotingArchiveGeneration, .failedRecoverable, .superseded],
            .promotingArchiveGeneration: [.archiveVerified, .failedRecoverable, .recoveryRequired, .superseded],
            .archiveVerified: [.archiveVerified],
            .removingActiveCopy: [.evictingProviderCache, .archiveVerified, .recoveryRequired, .superseded],
            .evictingProviderCache: [.archivedOnlineOnly, .archivedLocal, .recoveryRequired, .superseded],
            .archivedOnlineOnly: [.archiveVerified],
            .archivedLocal: [.archiveVerified],
            .failedRecoverable: Set(archivePhases).union([.recoveryRequired, .superseded]),
            .recoveryRequired: [.archiveVerified],
            .superseded: [],
            .materializingArchive: [],
            .copyingToActiveStaging: [],
            .verifyingActiveStaging: [],
            .promotingActiveCopy: [],
            .readyLocal: [],
            .openingInCubase: [],
        ]
        XCTAssertEqual(Set(expected.keys), Set(VaultTransferState.allCases))
        for state in VaultTransferState.allCases {
            XCTAssertEqual(machine.allowedDestinations(from: state), expected[state], "\(state)")
            for destination in expected[state] ?? [] {
                XCTAssertEqual(try machine.applying(.advance(to: destination), to: state), destination)
            }
        }
    }

    /// Every edge the Vault suites made (step 1 of the state machine plan) is
    /// legal, so the engines' checked writes cannot refuse a path a test knows.
    func testTableContainsEveryObservedEdge() throws {
        let evidence = VaultRemovalEvidence(manifestVerified: true, archiveDurability: .verifiedLocal, metadataPersisted: true)
        for edge in VaultObservedEdges.transfer {
            if edge == VaultTransferEdge(.archiveVerified, .removingActiveCopy) {
                XCTAssertEqual(try machine.applying(.beginRemovingActiveCopy(evidence), to: edge.from), edge.to)
            } else {
                XCTAssertTrue(machine.allowedDestinations(from: edge.from).contains(edge.to), "missing \(edge)")
            }
        }
    }

    func testTableRejectsEdgesNoPathMakes() {
        let illegal: [VaultTransferEdge] = [
            // A verified copy fails only after its save failed; the journal keeps it.
            .init(.archiveVerified, .failedRecoverable),
            .init(.archivedLocal, .failedRecoverable),
            .init(.archivedOnlineOnly, .failedRecoverable),
            // Skipping a phase, or leaving review without the person's recovery.
            .init(.copyingToArchiveStaging, .promotingArchiveGeneration),
            .init(.archiveVerified, .archivedLocal),
            .init(.removingActiveCopy, .archivedLocal),
            .init(.recoveryRequired, .removingActiveCopy),
            .init(.recoveryRequired, .failedRecoverable),
            .init(.failedRecoverable, .archiveVerified),
            .init(.failedRecoverable, .removingActiveCopy),
            .init(.failedRecoverable, .evictingProviderCache),
            // A retired or never-held state goes nowhere.
            .init(.superseded, .activeLocal),
            .init(.superseded, .archiveVerified),
            .init(.archivedLocal, .materializingArchive),
            .init(.readyLocal, .openingInCubase),
        ]
        for edge in illegal {
            XCTAssertThrowsError(try machine.applying(.advance(to: edge.to), to: edge.from), "\(edge)") {
                XCTAssertEqual($0 as? VaultTransitionError, .illegal(from: edge.from, to: edge.to))
            }
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

    func testActiveRemovalPermitsOnlyVerifiedLocalAndSyncedToProvider() throws {
        let durabilities: [VaultDurability] = [.verifiedLocal, .syncedToProvider, .independentlyBackedUp]
        for durability in durabilities {
            for manifestVerified in [false, true] {
                for metadataPersisted in [false, true] {
                    let evidence = VaultRemovalEvidence(
                        manifestVerified: manifestVerified,
                        archiveDurability: durability,
                        metadataPersisted: metadataPersisted
                    )
                    let expected = manifestVerified && metadataPersisted
                        && (durability == .verifiedLocal || durability == .syncedToProvider)
                    XCTAssertEqual(
                        evidence.permitsActiveCopyRemoval,
                        expected,
                        "durability=\(durability) manifest=\(manifestVerified) metadata=\(metadataPersisted)"
                    )
                    if expected {
                        XCTAssertEqual(
                            try machine.applying(.beginRemovingActiveCopy(evidence), to: .archiveVerified),
                            .removingActiveCopy,
                            "durability=\(durability)"
                        )
                    } else {
                        XCTAssertThrowsError(
                            try machine.applying(.beginRemovingActiveCopy(evidence), to: .archiveVerified),
                            "durability=\(durability) manifest=\(manifestVerified) metadata=\(metadataPersisted) must stay fail-closed"
                        ) { XCTAssertEqual($0 as? VaultTransitionError, .removalNotProven) }
                    }
                }
            }
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
}
