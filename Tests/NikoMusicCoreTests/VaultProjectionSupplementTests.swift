import CryptoKit
import Darwin
import Foundation
import SQLite3
import XCTest
@testable import NikoMusicCore

final class VaultProjectionSupplementTests: XCTestCase {
    func testLegacySupplementMutationDuringEvidenceObservationPersistsIdentityMismatchWithoutCAS() async throws {
        let fixture = try LegacyProjectionFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        try store.save(fixture.legacyTransfer)
        let projectionStore = ProjectionStoreSpy(store: store)
        var restore = VaultRestoreRecord(
            projectID: fixture.projectID,
            archiveGenerationURL: fixture.generation,
            stagingURL: fixture.active.appendingPathComponent(".niko-staging/identity-race"),
            destinationURL: fixture.active.appendingPathComponent("Restored/Legacy Song"),
            manifest: fixture.legacyManifest,
            archiveTransferID: fixture.legacyTransfer.id,
            archiveTransferState: fixture.legacyTransfer.state,
            requiresArchiveMaterialization: false
        )
        restore.failureReason = .legacyProjectionEvidenceUnavailable
        try store.saveRestore(restore)
        let mutationFlag = SupplementMutationFlag()
        let projectFile = fixture.generation.appendingPathComponent("Legacy Song.cpr")
        let builder = VaultProjectionSupplementBuilder(
            beforeObservedBuild: {
                try Data(repeating: 0x58, count: 13).write(to: projectFile)
                mutationFlag.set()
            }
        )

        do {
            let supplement = try builder.build(
                at: fixture.generation,
                verifiedAgainst: fixture.legacyManifest
            )
            _ = try projectionStore.compareAndSetProjectionSupplement(
                supplement,
                transferID: fixture.legacyTransfer.id,
                expectedManifest: fixture.legacyManifest,
                expectedDestinationURL: fixture.generation,
                expectedState: fixture.legacyTransfer.state
            )
            restore.failureReason = nil
            try store.saveRestore(restore)
        } catch VaultProjectionSupplementError.identityMismatch {
            restore.failureReason = .legacyProjectionIdentityMismatch
            try store.saveRestore(restore)
        }

        XCTAssertTrue(mutationFlag.value)
        XCTAssertEqual(projectionStore.mergeCount, 0)
        XCTAssertNil(try store.record(id: fixture.legacyTransfer.id)?.projectionSupplement)
        let persistedRestore = try XCTUnwrap(try store.recoverableRestoreRecords().first)
        XCTAssertEqual(persistedRestore.failureReason?.rawValue, "legacyProjectionIdentityMismatch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: persistedRestore.stagingURL.path))
    }

    func testSupplementCASRejectsStoredManifestContentDriftWithSameManifestIDAndPreservesReplacement() throws {
        enum Drift: CaseIterable { case type, size, hash }

        for drift in Drift.allCases {
            let fixture = try LegacyProjectionFixture()
            defer { fixture.remove() }
            let database = try SQLiteArchiveDatabase(databaseURL: fixture.databaseURL)
            let store = try SQLiteVaultTransferStore(database: database)
            try store.save(fixture.legacyTransfer)
            let expectedManifest = fixture.legacyManifest
            let supplement = try VaultProjectionSupplementBuilder().build(
                at: fixture.generation,
                verifiedAgainst: expectedManifest
            )
            let originalEntry = try XCTUnwrap(expectedManifest.entries.first)
            let replacementEntry: VaultManifest.Entry
            switch drift {
            case .type:
                replacementEntry = .init(
                    relativePath: originalEntry.relativePath,
                    type: .directory,
                    byteCount: 0,
                    modifiedAt: originalEntry.modifiedAt,
                    sha256: nil
                )
            case .size:
                replacementEntry = .init(
                    relativePath: originalEntry.relativePath,
                    type: originalEntry.type,
                    byteCount: originalEntry.byteCount + 1,
                    modifiedAt: originalEntry.modifiedAt,
                    sha256: originalEntry.sha256
                )
            case .hash:
                replacementEntry = .init(
                    relativePath: originalEntry.relativePath,
                    type: originalEntry.type,
                    byteCount: originalEntry.byteCount,
                    modifiedAt: originalEntry.modifiedAt,
                    sha256: String(repeating: "f", count: 64)
                )
            }
            var replacement = fixture.legacyTransfer
            replacement.manifest = VaultManifest(
                id: expectedManifest.id,
                createdAt: expectedManifest.createdAt,
                entries: [replacementEntry]
            )
            try store.save(replacement)
            let replacementSQLTimestamp = try sqliteTransferUpdatedAt(database, id: replacement.id)

            XCTAssertThrowsError(try compareAndSetProjectionSupplementBindingExpectedManifest(
                store: store,
                supplement: supplement,
                transferID: replacement.id,
                expectedManifest: expectedManifest,
                expectedDestinationURL: replacement.destinationURL,
                expectedState: replacement.state
            ))

            let unchanged = try XCTUnwrap(store.record(id: replacement.id))
            XCTAssertEqual(unchanged.manifest, replacement.manifest)
            XCTAssertNil(unchanged.projectionSupplement)
            XCTAssertEqual(unchanged.state, replacement.state)
            XCTAssertEqual(unchanged.updatedAt, replacement.updatedAt)
            XCTAssertEqual(
                try sqliteTransferUpdatedAt(database, id: replacement.id),
                replacementSQLTimestamp
            )
        }
    }

    func testProjectionSupplementMergePreservesManifestIdentityAndGenerationBinding() throws {
        let fixture = try LegacyProjectionFixture()
        defer { fixture.remove() }
        let database = try SQLiteArchiveDatabase(databaseURL: fixture.databaseURL)
        let store = try SQLiteVaultTransferStore(database: database)
        try store.save(fixture.legacyTransfer)
        let sqlUpdatedAt = try sqliteTransferUpdatedAt(database, id: fixture.legacyTransfer.id)
        let supplement = try VaultProjectionSupplementBuilder().build(
            at: fixture.generation,
            verifiedAgainst: fixture.legacyManifest
        )

        let merged = try store.compareAndSetProjectionSupplement(
            supplement,
            transferID: fixture.legacyTransfer.id,
            expectedManifest: fixture.legacyManifest,
            expectedDestinationURL: fixture.generation,
            expectedState: .archiveVerified
        )

        XCTAssertEqual(merged.id, fixture.legacyTransfer.id)
        XCTAssertEqual(merged.manifestID, fixture.legacyTransfer.manifestID)
        XCTAssertEqual(merged.manifest, fixture.legacyManifest)
        XCTAssertEqual(merged.destinationURL, fixture.generation)
        XCTAssertEqual(merged.state, fixture.legacyTransfer.state)
        XCTAssertEqual(merged.durability, fixture.legacyTransfer.durability)
        XCTAssertEqual(merged.createdAt, fixture.legacyTransfer.createdAt)
        XCTAssertEqual(merged.updatedAt, fixture.legacyTransfer.updatedAt)
        XCTAssertEqual(merged.projectionSupplement, supplement)
        XCTAssertEqual(try sqliteTransferUpdatedAt(database, id: merged.id), sqlUpdatedAt)
    }

    func testSupplementRejectsMismatchExtraSymlinkAndUnreadableWithoutPersistence() throws {
        enum Mutation: CaseIterable { case mismatch, extra, symlink, unreadable }

        for mutation in Mutation.allCases {
            let fixture = try LegacyProjectionFixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            try store.save(fixture.legacyTransfer)
            let projectFile = fixture.generation.appendingPathComponent("Legacy Song.cpr")
            var unreadableURL: URL?
            switch mutation {
            case .mismatch:
                try Data("changed".utf8).write(to: projectFile)
            case .extra:
                try Data("unexpected".utf8).write(
                    to: fixture.generation.appendingPathComponent("Unexpected.wav")
                )
            case .symlink:
                let outside = fixture.root.appendingPathComponent("outside.cpr")
                try Data("outside".utf8).write(to: outside)
                try FileManager.default.removeItem(at: projectFile)
                try FileManager.default.createSymbolicLink(at: projectFile, withDestinationURL: outside)
            case .unreadable:
                unreadableURL = projectFile
                XCTAssertEqual(chmod(projectFile.path, 0), 0)
            }
            defer {
                if let unreadableURL { chmod(unreadableURL.path, S_IRUSR | S_IWUSR) }
            }

            XCTAssertThrowsError(
                try VaultProjectionSupplementBuilder().build(
                    at: fixture.generation,
                    verifiedAgainst: fixture.legacyManifest
                ),
                "\(mutation) must fail exact legacy verification before persistence"
            )
            XCTAssertNil(try store.record(id: fixture.legacyTransfer.id)?.projectionSupplement)
        }
    }

    func testSupplementCASConflictsRollbackWithoutMovingTimestamps() throws {
        let fixture = try LegacyProjectionFixture()
        defer { fixture.remove() }
        let database = try SQLiteArchiveDatabase(databaseURL: fixture.databaseURL)
        let store = try SQLiteVaultTransferStore(database: database)
        try store.save(fixture.legacyTransfer)
        let supplement = try VaultProjectionSupplementBuilder().build(
            at: fixture.generation,
            verifiedAgainst: fixture.legacyManifest
        )
        let sqlUpdatedAt = try sqliteTransferUpdatedAt(database, id: fixture.legacyTransfer.id)
        let partial = VaultProjectionSupplement(
            rootAllocatedByteCount: supplement.rootAllocatedByteCount,
            rootExtendedAttributeBytes: supplement.rootExtendedAttributeBytes,
            entries: []
        )
        let conflicts: [(VaultManifest, URL, VaultTransferState, VaultProjectionSupplement)] = [
            (VaultManifest(id: UUID(), entries: fixture.legacyManifest.entries), fixture.generation, .archiveVerified, supplement),
            (fixture.legacyManifest, fixture.root.appendingPathComponent("other"), .archiveVerified, supplement),
            (fixture.legacyManifest, fixture.generation, .archivedOnlineOnly, supplement),
            (fixture.legacyManifest, fixture.generation, .archiveVerified, partial),
        ]

        for (expectedManifest, destination, state, candidate) in conflicts {
            XCTAssertThrowsError(try store.compareAndSetProjectionSupplement(
                candidate,
                transferID: fixture.legacyTransfer.id,
                expectedManifest: expectedManifest,
                expectedDestinationURL: destination,
                expectedState: state
            ))
            let unchanged = try XCTUnwrap(store.record(id: fixture.legacyTransfer.id))
            XCTAssertNil(unchanged.projectionSupplement)
            XCTAssertEqual(unchanged.updatedAt, fixture.legacyTransfer.updatedAt)
            XCTAssertEqual(try sqliteTransferUpdatedAt(database, id: unchanged.id), sqlUpdatedAt)
        }
    }

    func testFullyLocalLegacyRestorePersistsSupplementBeforeActiveAdmissionAndRelaunchReusesIt() async throws {
        let fixture = try LegacyProjectionFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        try store.save(fixture.legacyTransfer)
        let projectionStore = ProjectionStoreSpy(store: store)
        let provider = SupplementProviderSpy(locality: .fullyLocalCurrent)
        let firstAdmission = SupplementAdmissionSpy()
        let first = fixture.engine(
            store: store,
            projectionStore: projectionStore,
            provider: provider,
            admission: { request, _ in
                firstAdmission.record(request)
                if request.target == .active {
                    XCTAssertNotNil(try store.record(id: fixture.legacyTransfer.id)?.projectionSupplement)
                }
                throw SupplementTestError.stop
            }
        )

        await XCTAssertThrowsErrorAsync(
            try await first.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Legacy Song"
            )
        )
        XCTAssertEqual(projectionStore.mergeCount, 1)
        XCTAssertEqual(firstAdmission.requests.map(\.target), [.active])
        XCTAssertNotNil(try store.record(id: fixture.legacyTransfer.id)?.projectionSupplement)

        let secondAdmission = SupplementAdmissionSpy()
        let second = fixture.engine(
            store: store,
            projectionStore: projectionStore,
            provider: provider,
            admission: { request, _ in
                secondAdmission.record(request)
                throw SupplementTestError.stop
            }
        )
        _ = await second.recoverAtLaunch()

        XCTAssertEqual(projectionStore.mergeCount, 1, "relaunch must reuse the persisted supplement")
        XCTAssertEqual(secondAdmission.requests.map(\.target), [.active])
    }

    func testLegacyOnlineUnknownAndErrorPersistReviewWithZeroHydrationOrCopy() async throws {
        let outcomes: [SupplementProviderSpy.Outcome] = [
            .locality(.materializationRequired),
            .locality(.unknown),
            .failure,
        ]
        for outcome in outcomes {
            let fixture = try LegacyProjectionFixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            try store.save(fixture.legacyTransfer)
            let provider = SupplementProviderSpy(outcome: outcome)
            let admission = SupplementAdmissionSpy()
            let hashSpy = SupplementHashSpy()
            let engine = fixture.engine(
                store: store,
                projectionStore: ProjectionStoreSpy(store: store),
                provider: provider,
                admission: { request, operation in
                    admission.record(request)
                    try await operation()
                },
                manifestBuilder: VaultManifestBuilder(contentHasher: hashSpy.hash)
            )

            await XCTAssertThrowsErrorAsync(
                try await engine.restoreAndOpen(
                    projectID: fixture.projectID,
                    destinationRelativePath: "Restored/Legacy Song"
                )
            )

            let restore = try XCTUnwrap(try store.recoverableRestoreRecords().first)
            XCTAssertEqual(restore.failureReason, .legacyProjectionEvidenceUnavailable)
            XCTAssertEqual(restore.reviewGenerationURL, fixture.generation)
            XCTAssertEqual(provider.prepareCount, 0)
            XCTAssertEqual(provider.materializeCount, 0)
            XCTAssertTrue(admission.requests.isEmpty)
            XCTAssertEqual(hashSpy.openCount, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: restore.stagingURL.path))
        }
    }

    func testSupplementPersistenceFailureAndCASRaceFailClosedBeforeCopy() async throws {
        for mode in [ProjectionStoreSpy.Mode.persistenceFailure, .conflict] {
            let fixture = try LegacyProjectionFixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            try store.save(fixture.legacyTransfer)
            let projectionStore = ProjectionStoreSpy(store: store, mode: mode)
            let admission = SupplementAdmissionSpy()
            let engine = fixture.engine(
                store: store,
                projectionStore: projectionStore,
                provider: SupplementProviderSpy(locality: .fullyLocalCurrent),
                admission: { request, operation in
                    admission.record(request)
                    try await operation()
                }
            )

            await XCTAssertThrowsErrorAsync(
                try await engine.restoreAndOpen(
                    projectID: fixture.projectID,
                    destinationRelativePath: "Restored/Legacy Song"
                )
            )

            XCTAssertTrue(admission.requests.isEmpty)
            XCTAssertNil(try store.record(id: fixture.legacyTransfer.id)?.projectionSupplement)
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: fixture.active.appendingPathComponent(".niko-staging").path
            ))
        }
    }

    func testActiveRestoreProjectsFreshLiveSourceAfterPostManifestXattrGrowth() async throws {
        let fixture = try LegacyProjectionFixture(useAllocationAwareManifest: true)
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        try store.save(fixture.legacyTransfer)
        let file = fixture.generation.appendingPathComponent("Legacy Song.cpr")
        let xattr = [UInt8](repeating: 7, count: 128 * 1_024)
        let result = file.withUnsafeFileSystemRepresentation { path in
            xattr.withUnsafeBytes { bytes in
                setxattr(path, "com.niko.restore-growth", bytes.baseAddress, bytes.count, 0, 0)
            }
        }
        XCTAssertEqual(result, 0)
        let liveAfterGrowth = try VaultManifestBuilder().build(at: fixture.generation)
        let beforeXattrs = fixture.liveManifest.entries.first?.extendedAttributeBytes ?? 0
        let afterXattrs = liveAfterGrowth.entries.first?.extendedAttributeBytes ?? 0
        XCTAssertGreaterThanOrEqual(afterXattrs - beforeXattrs, Int64(xattr.count))
        let admission = SupplementAdmissionSpy()
        let engine = fixture.engine(
            store: store,
            projectionStore: ProjectionStoreSpy(store: store),
            provider: SupplementProviderSpy(locality: .fullyLocalCurrent),
            admission: { request, _ in
                admission.record(request)
                guard request.target == .active else { throw SupplementTestError.stop }
                XCTAssertEqual(request.projection, .liveSource(fixture.generation))
                XCTAssertNil(request.manifest)
                throw SupplementTestError.stop
            }
        )

        await XCTAssertThrowsErrorAsync(
            try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Legacy Song"
            )
        )
        XCTAssertEqual(admission.requests.map(\.target), [.active])
    }

    func testRetryAndRecoveryRejectPreexistingSupplementWithoutExactArchiveTransferBinding() async throws {
        enum BindingFailure: CaseIterable {
            case projectionStoreAbsent
            case transferRecordAbsent
            case archiveTransferIDAbsent
            case projectMismatch
            case nonterminalState
            case destinationMismatchWithinGenerations
            case immutableManifestMismatch
        }
        enum Invocation: CaseIterable { case retry, recovery }

        for invocation in Invocation.allCases {
            for failure in BindingFailure.allCases {
                let fixture = try LegacyProjectionFixture()
                defer { fixture.remove() }
                let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
                let supplement = try VaultProjectionSupplementBuilder().build(
                    at: fixture.generation,
                    verifiedAgainst: fixture.legacyManifest
                )
                var storedTransfer = fixture.legacyTransfer
                storedTransfer.projectionSupplement = supplement
                var archiveTransferID: UUID? = storedTransfer.id
                var projectionStore: (any VaultProjectionSupplementStoring)? = store

                switch failure {
                case .projectionStoreAbsent:
                    projectionStore = nil
                case .transferRecordAbsent:
                    break
                case .archiveTransferIDAbsent:
                    archiveTransferID = nil
                case .projectMismatch:
                    var mismatch = VaultTransferRecord(
                        id: storedTransfer.id,
                        projectID: ProjectID(),
                        sourceURL: storedTransfer.sourceURL,
                        stagingURL: storedTransfer.stagingURL,
                        destinationURL: storedTransfer.destinationURL,
                        state: storedTransfer.state,
                        createdAt: storedTransfer.createdAt
                    )
                    mismatch.manifestID = storedTransfer.manifestID
                    mismatch.manifest = storedTransfer.manifest
                    mismatch.projectionSupplement = supplement
                    mismatch.durability = storedTransfer.durability
                    storedTransfer = mismatch
                case .nonterminalState:
                    storedTransfer.state = .failedRecoverable
                case .destinationMismatchWithinGenerations:
                    storedTransfer.destinationURL = fixture.generation
                        .deletingLastPathComponent()
                        .appendingPathComponent("different-generation", isDirectory: true)
                case .immutableManifestMismatch:
                    let original = try XCTUnwrap(fixture.legacyManifest.entries.first)
                    let changed = VaultManifest.Entry(
                        relativePath: original.relativePath,
                        type: original.type,
                        byteCount: original.byteCount + 1,
                        modifiedAt: original.modifiedAt,
                        sha256: String(repeating: "f", count: 64)
                    )
                    storedTransfer.manifest = VaultManifest(
                        id: fixture.legacyManifest.id,
                        createdAt: fixture.legacyManifest.createdAt,
                        entries: [changed]
                    )
                }
                if failure != .transferRecordAbsent {
                    try store.save(storedTransfer)
                }

                let restoreID = UUID()
                let stagingURL = fixture.active
                    .appendingPathComponent(".niko-staging", isDirectory: true)
                    .appendingPathComponent(restoreID.uuidString.lowercased(), isDirectory: true)
                var restore = VaultRestoreRecord(
                    id: restoreID,
                    projectID: fixture.projectID,
                    archiveGenerationURL: fixture.generation,
                    stagingURL: stagingURL,
                    destinationURL: fixture.active.appendingPathComponent("Restored/Legacy Song", isDirectory: true),
                    manifest: fixture.legacyManifest,
                    archiveTransferID: archiveTransferID,
                    archiveTransferState: .archiveVerified,
                    requiresArchiveMaterialization: false,
                    projectionSupplement: supplement
                )
                if invocation == .retry {
                    restore.failureReason = .legacyProjectionEvidenceUnavailable
                }
                try store.saveRestore(restore)

                let provider = SupplementProviderSpy(locality: .fullyLocalCurrent)
                let admission = SupplementAdmissionSpy()
                let sideEffects = SupplementRestoreSideEffectSpy()
                let engine = LocalVaultRestoreEngine(
                    activeRoot: fixture.active,
                    archiveRoot: fixture.root.appendingPathComponent("Archive"),
                    activeRootID: UUID(),
                    resolver: store,
                    store: store,
                    projectionStore: projectionStore,
                    provider: provider,
                    catalog: sideEffects,
                    projectOpener: sideEffects,
                    writeAdmission: { request, _ in
                        admission.record(request)
                        throw SupplementTestError.stop
                    }
                )

                switch invocation {
                case .retry:
                    await XCTAssertThrowsErrorAsync(try await engine.retryRestore(id: restoreID))
                case .recovery:
                    _ = await engine.recoverAtLaunch()
                }

                let persisted = try XCTUnwrap(try store.restoreRecord(id: restoreID))
                XCTAssertEqual(
                    persisted.failureReason?.rawValue,
                    "archiveTransferBindingUnavailable",
                    "\(invocation)/\(failure) must persist a typed Review blocker"
                )
                XCTAssertTrue(admission.requests.isEmpty, "\(invocation)/\(failure) must fail before admission")
                XCTAssertEqual(provider.materializeCount, 0, "\(invocation)/\(failure) must not hydrate")
                XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
                XCTAssertEqual(sideEffects.catalogCount, 0)
                XCTAssertEqual(sideEffects.openCount, 0)
                XCTAssertNil(persisted.completedAt)
            }
        }
    }

    func testRetryAndRecoveryAdoptCommittedTransferSupplementAfterRestorePersistCrashWindow() async throws {
        enum Invocation: CaseIterable { case retry, recovery }
        enum Evidence: CaseIterable { case matching, invalidTransferSupplement }

        for invocation in Invocation.allCases {
            for evidence in Evidence.allCases {
                let fixture = try LegacyProjectionFixture()
                defer { fixture.remove() }
                let database = try SQLiteArchiveDatabase(databaseURL: fixture.databaseURL)
                let store = try SQLiteVaultTransferStore(database: database)
                try store.save(fixture.legacyTransfer)
                let supplement = try VaultProjectionSupplementBuilder().build(
                    at: fixture.generation,
                    verifiedAgainst: fixture.legacyManifest
                )
                _ = try store.compareAndSetProjectionSupplement(
                    supplement,
                    transferID: fixture.legacyTransfer.id,
                    expectedManifest: fixture.legacyManifest,
                    expectedDestinationURL: fixture.generation,
                    expectedState: .archiveVerified
                )
                if evidence == .invalidTransferSupplement {
                    var invalid = try XCTUnwrap(try store.record(id: fixture.legacyTransfer.id))
                    invalid.projectionSupplement = VaultProjectionSupplement(
                        rootAllocatedByteCount: supplement.rootAllocatedByteCount,
                        rootExtendedAttributeBytes: supplement.rootExtendedAttributeBytes,
                        entries: []
                    )
                    try store.save(invalid)
                }

                let restoreID = UUID()
                let stagingURL = fixture.active
                    .appendingPathComponent(".niko-staging", isDirectory: true)
                    .appendingPathComponent(restoreID.uuidString.lowercased(), isDirectory: true)
                let destinationURL = fixture.active
                    .appendingPathComponent("Restored", isDirectory: true)
                    .appendingPathComponent("\(invocation)-\(evidence)", isDirectory: true)
                let restore = VaultRestoreRecord(
                    id: restoreID,
                    projectID: fixture.projectID,
                    archiveGenerationURL: fixture.generation,
                    stagingURL: stagingURL,
                    destinationURL: destinationURL,
                    manifest: fixture.legacyManifest,
                    archiveTransferID: fixture.legacyTransfer.id,
                    archiveTransferState: .archiveVerified,
                    requiresArchiveMaterialization: false,
                    projectionSupplement: nil
                )
                try store.saveRestore(restore)

                let admission = SupplementAdmissionSpy()
                let sideEffects = SupplementRestoreSideEffectSpy()
                let phaseEvidence = SupplementPhaseEvidenceSpy()
                let engine = LocalVaultRestoreEngine(
                    activeRoot: fixture.active,
                    archiveRoot: fixture.root.appendingPathComponent("Archive"),
                    activeRootID: UUID(),
                    resolver: store,
                    store: store,
                    projectionStore: store,
                    provider: SupplementProviderSpy(locality: .fullyLocalCurrent),
                    catalog: sideEffects,
                    projectOpener: sideEffects,
                    faultInjector: { point, record in
                        guard point == .materializingArchive else { return }
                        let persisted = try store.restoreRecord(id: record.id)
                        phaseEvidence.record(
                            persisted?.id == restoreID
                                && persisted?.projectionSupplement == supplement
                        )
                    },
                    writeAdmission: { request, operation in
                        admission.record(request)
                        try await operation()
                    }
                )

                let result: VaultRestoreRecord?
                switch invocation {
                case .retry:
                    result = try? await engine.retryRestore(id: restoreID)
                case .recovery:
                    result = await engine.recoverAtLaunch().first
                }

                let persisted = try XCTUnwrap(try store.restoreRecord(id: restoreID))
                XCTAssertEqual(try sqliteRestoreRowCount(database), 1, "\(invocation)/\(evidence) must reuse one job")
                if evidence == .matching {
                    XCTAssertEqual(result?.id, restoreID)
                    XCTAssertEqual(persisted.id, restoreID)
                    XCTAssertEqual(persisted.projectionSupplement, supplement)
                    XCTAssertNil(persisted.failureReason)
                    XCTAssertNotNil(persisted.completedAt)
                    XCTAssertEqual(phaseEvidence.values, [true], "evidence must be persisted before the first phase")
                    XCTAssertEqual(admission.requests.map(\.target), [.active])
                    XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
                    XCTAssertEqual(sideEffects.catalogCount, 1)
                    XCTAssertEqual(sideEffects.openCount, 1)
                } else {
                    XCTAssertNil(result?.completedAt)
                    XCTAssertEqual(persisted.failureReason, .archiveTransferBindingUnavailable)
                    XCTAssertNil(persisted.projectionSupplement)
                    XCTAssertTrue(phaseEvidence.values.isEmpty)
                    XCTAssertTrue(admission.requests.isEmpty)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
                    XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
                    XCTAssertEqual(sideEffects.catalogCount, 0)
                    XCTAssertEqual(sideEffects.openCount, 0)
                }
            }
        }
    }

    func testAdoptingCommittedSupplementRetainsLegacyBlockerUntilExactArchiveVerification() async throws {
        let fixture = try LegacyProjectionFixture()
        defer { fixture.remove() }
        let database = try SQLiteArchiveDatabase(databaseURL: fixture.databaseURL)
        let store = try SQLiteVaultTransferStore(database: database)
        try store.save(fixture.legacyTransfer)
        let supplement = try VaultProjectionSupplementBuilder().build(
            at: fixture.generation,
            verifiedAgainst: fixture.legacyManifest
        )
        _ = try store.compareAndSetProjectionSupplement(
            supplement,
            transferID: fixture.legacyTransfer.id,
            expectedManifest: fixture.legacyManifest,
            expectedDestinationURL: fixture.generation,
            expectedState: .archiveVerified
        )

        let restoreID = UUID()
        let stagingURL = fixture.active
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(restoreID.uuidString.lowercased(), isDirectory: true)
        let destinationURL = fixture.active
            .appendingPathComponent("Restored/Crash Window", isDirectory: true)
        var restore = VaultRestoreRecord(
            id: restoreID,
            projectID: fixture.projectID,
            archiveGenerationURL: fixture.generation,
            stagingURL: stagingURL,
            destinationURL: destinationURL,
            manifest: fixture.legacyManifest,
            archiveTransferID: fixture.legacyTransfer.id,
            archiveTransferState: .archiveVerified,
            requiresArchiveMaterialization: false,
            projectionSupplement: nil
        )
        restore.failureReason = .legacyProjectionEvidenceUnavailable
        restore.error = "Archive projection evidence still needs exact verification."
        try store.saveRestore(restore)

        let admission = SupplementAdmissionSpy()
        let provider = SupplementProviderSpy(locality: .fullyLocalCurrent)
        let sideEffects = SupplementRestoreSideEffectSpy()
        let hashSpy = SupplementHashSpy()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.root.appendingPathComponent("Archive"),
            activeRootID: UUID(),
            resolver: store,
            store: store,
            projectionStore: store,
            provider: provider,
            catalog: sideEffects,
            projectOpener: sideEffects,
            faultInjector: { point, _ in
                guard point == .materializingArchive else { return }
                throw VaultTransferInterruption()
            },
            writeAdmission: { request, operation in
                admission.record(request)
                try await operation()
            },
            manifestBuilder: VaultManifestBuilder(contentHasher: hashSpy.hash)
        )

        do {
            _ = try await engine.retryRestore(id: restoreID)
            XCTFail("expected interruption before exact archive verification")
        } catch is VaultTransferInterruption {}

        let persisted = try XCTUnwrap(try store.restoreRecord(id: restoreID))
        XCTAssertEqual(try sqliteRestoreRowCount(database), 1)
        XCTAssertEqual(persisted.id, restoreID)
        XCTAssertEqual(persisted.projectionSupplement, supplement)
        XCTAssertEqual(persisted.phase, .materializingArchive)
        XCTAssertEqual(persisted.failureReason, .legacyProjectionEvidenceUnavailable)
        XCTAssertEqual(persisted.error, "Archive projection evidence still needs exact verification.")
        XCTAssertTrue(admission.requests.isEmpty)
        XCTAssertEqual(provider.prepareCount, 0)
        XCTAssertEqual(provider.materializeCount, 0)
        XCTAssertEqual(hashSpy.openCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertEqual(sideEffects.catalogCount, 0)
        XCTAssertEqual(sideEffects.openCount, 0)
    }

}

private struct LegacyProjectionFixture {
    let root: URL
    let active: URL
    let generation: URL
    let databaseURL: URL
    let projectID = ProjectID()
    let liveManifest: VaultManifest
    let legacyManifest: VaultManifest
    let legacyTransfer: VaultTransferRecord

    init(useAllocationAwareManifest: Bool = false) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("projection-supplement-\(UUID().uuidString)", isDirectory: true)
        active = root.appendingPathComponent("Active", isDirectory: true)
        generation = root.appendingPathComponent("Archive/generations/verified", isDirectory: true)
        databaseURL = root.appendingPathComponent("State/vault.sqlite")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        try Data("legacy-cubase".utf8).write(to: generation.appendingPathComponent("Legacy Song.cpr"))
        liveManifest = try VaultManifestBuilder().build(at: generation)
        legacyManifest = useAllocationAwareManifest ? liveManifest : Self.legacy(from: liveManifest)
        var transfer = VaultTransferRecord(
            projectID: projectID,
            sourceURL: active.appendingPathComponent("former-active"),
            stagingURL: root.appendingPathComponent("Archive/.niko-staging/old"),
            destinationURL: generation,
            state: .archiveVerified,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        transfer.manifestID = legacyManifest.id
        transfer.manifest = legacyManifest
        transfer.durability = .verifiedLocal
        legacyTransfer = transfer
    }

    func engine(
        store: SQLiteVaultTransferStore,
        projectionStore: any VaultProjectionSupplementStoring,
        provider: any ArchiveStorageProvider,
        admission: @escaping LocalVaultTransferEngine.WriteAdmission,
        manifestBuilder: VaultManifestBuilder? = nil
    ) -> LocalVaultRestoreEngine {
        LocalVaultRestoreEngine(
            activeRoot: active,
            archiveRoot: root.appendingPathComponent("Archive"),
            activeRootID: UUID(),
            resolver: store,
            store: store,
            projectionStore: projectionStore,
            provider: provider,
            catalog: SupplementCatalogSpy(),
            projectOpener: SupplementOpenerSpy(),
            writeAdmission: admission,
            manifestBuilder: manifestBuilder
        )
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    private static func legacy(from manifest: VaultManifest) -> VaultManifest {
        VaultManifest(
            id: manifest.id,
            createdAt: manifest.createdAt,
            entries: manifest.entries.map {
                .init(
                    relativePath: $0.relativePath,
                    type: $0.type,
                    byteCount: $0.byteCount,
                    modifiedAt: $0.modifiedAt,
                    sha256: $0.sha256
                )
            }
        )
    }
}

private final class SupplementMutationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false
    var value: Bool { lock.withLock { storedValue } }
    func set() { lock.withLock { storedValue = true } }
}

private func compareAndSetProjectionSupplementBindingExpectedManifest(
    store: SQLiteVaultTransferStore,
    supplement: VaultProjectionSupplement,
    transferID: UUID,
    expectedManifest: VaultManifest,
    expectedDestinationURL: URL,
    expectedState: VaultTransferState
) throws -> VaultTransferRecord {
    // RED adapter: production currently accepts only the UUID and therefore
    // discards the immutable content fingerprint carried by expectedManifest.
    try store.compareAndSetProjectionSupplement(
        supplement,
        transferID: transferID,
        expectedManifest: expectedManifest,
        expectedDestinationURL: expectedDestinationURL,
        expectedState: expectedState
    )
}

private final class ProjectionStoreSpy: VaultProjectionSupplementStoring, @unchecked Sendable {
    enum Mode { case normal, persistenceFailure, conflict }
    private let lock = NSLock()
    private let store: SQLiteVaultTransferStore
    private let mode: Mode
    private var storedMergeCount = 0

    init(store: SQLiteVaultTransferStore, mode: Mode = .normal) {
        self.store = store
        self.mode = mode
    }

    var mergeCount: Int { lock.withLock { storedMergeCount } }

    func record(id: UUID) throws -> VaultTransferRecord? {
        try store.record(id: id)
    }

    func compareAndSetProjectionSupplement(
        _ supplement: VaultProjectionSupplement,
        transferID: UUID,
        expectedManifest: VaultManifest,
        expectedDestinationURL: URL,
        expectedState: VaultTransferState
    ) throws -> VaultTransferRecord {
        lock.withLock { storedMergeCount += 1 }
        switch mode {
        case .normal:
            return try store.compareAndSetProjectionSupplement(
                supplement,
                transferID: transferID,
                expectedManifest: expectedManifest,
                expectedDestinationURL: expectedDestinationURL,
                expectedState: expectedState
            )
        case .persistenceFailure:
            throw SupplementTestError.persistence
        case .conflict:
            throw VaultProjectionSupplementError.conflict
        }
    }
}

private final class SupplementProviderSpy: ArchiveStorageProvider, @unchecked Sendable {
    enum Outcome { case locality(ArchiveStorageLocality), failure }
    private let lock = NSLock()
    private let outcome: Outcome
    private var storedPrepareCount = 0
    private var storedMaterializeCount = 0

    init(locality: ArchiveStorageLocality) { outcome = .locality(locality) }
    init(outcome: Outcome) { self.outcome = outcome }
    var prepareCount: Int { lock.withLock { storedPrepareCount } }
    var materializeCount: Int { lock.withLock { storedMaterializeCount } }

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: true, supportsEviction: false)
    }
    func currentLocality(at location: URL, manifest: VaultManifest) async throws -> ArchiveStorageLocality {
        switch outcome {
        case .locality(let locality): return locality
        case .failure: throw SupplementTestError.provider
        }
    }
    func prepareForRead(_ location: URL) async throws { lock.withLock { storedPrepareCount += 1 } }
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws { lock.withLock { storedMaterializeCount += 1 } }
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

private final class SupplementAdmissionSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [VaultWriteAdmissionRequest] = []
    var requests: [VaultWriteAdmissionRequest] { lock.withLock { storedRequests } }
    func record(_ request: VaultWriteAdmissionRequest) { lock.withLock { storedRequests.append(request) } }
}

private final class SupplementHashSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storedOpenCount = 0
    var openCount: Int { lock.withLock { storedOpenCount } }
    func hash(_ url: URL) throws -> (byteCount: Int64, sha256: String) {
        lock.withLock { storedOpenCount += 1 }
        let data = try Data(contentsOf: url)
        return (Int64(data.count), SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
}

private struct SupplementCatalogSpy: ActiveProjectLocationPersisting {
    func persistActiveLocation(projectID: ProjectID, location: ProjectLocation) throws {}
}

private struct SupplementOpenerSpy: VaultProjectOpening {
    func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult? { nil }
}

private final class SupplementRestoreSideEffectSpy: ActiveProjectLocationPersisting, VaultProjectOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCatalogCount = 0
    private var storedOpenCount = 0

    var catalogCount: Int { lock.withLock { storedCatalogCount } }
    var openCount: Int { lock.withLock { storedOpenCount } }

    func persistActiveLocation(projectID: ProjectID, location: ProjectLocation) throws {
        lock.withLock { storedCatalogCount += 1 }
    }

    func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult? {
        lock.withLock { storedOpenCount += 1 }
        return nil
    }
}

private final class SupplementPhaseEvidenceSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [Bool] = []
    var values: [Bool] { lock.withLock { storedValues } }
    func record(_ value: Bool) { lock.withLock { storedValues.append(value) } }
}

private enum SupplementTestError: Error { case stop, persistence, provider }

private func sqliteTransferUpdatedAt(_ database: SQLiteArchiveDatabase, id: UUID) throws -> Double {
    try database.withConnection { db in
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT updated_at FROM vault_transfers WHERE id=?;", -1, &statement, nil) == SQLITE_OK else {
            throw SupplementTestError.persistence
        }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else { throw SupplementTestError.persistence }
        return sqlite3_column_double(statement, 0)
    }
}

private func sqliteRestoreRowCount(_ database: SQLiteArchiveDatabase) throws -> Int {
    try database.withConnection { db in
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM vault_restores;", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            throw SupplementTestError.persistence
        }
        return Int(sqlite3_column_int64(statement, 0))
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected error", file: file, line: line)
    } catch {}
}
