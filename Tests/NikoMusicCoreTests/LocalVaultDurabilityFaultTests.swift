import Darwin
import Foundation
import XCTest
@testable import NikoMusicCore

/// Focused durability-boundary regressions for the Vault engine.
///
/// Scope: fresh provider barrier before destructive admission, journal-barrier
/// enforcement, legacy/mutation handling, survivor retirement safety, and
/// cancellation truthfulness at the exact remove boundary. Uses only UUID
/// fixtures in disposable temp dirs; never touches real drives. No power-cut
/// claim: success means the OS accepted the flush/journal sequence, not
/// hardware survival. Real temp syscalls are exercised separately from
/// simulated faults.
final class LocalVaultDurabilityFaultTests: XCTestCase {
    // MARK: - Fresh barrier before removal

    func testRemoveActiveCopyReRunsProviderBarrierForExactGeneration() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let provider = CountingFaultBarrierProvider(
            durability: .verifiedLocal,
            waitsForDurability: false
        )
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in }
        )
        let verified = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
        XCTAssertEqual(verified.durability, .verifiedLocal)
        let barriersAfterArchive = await provider.barrierCount()
        XCTAssertEqual(barriersAfterArchive, 2, "archive performs staging + promotion barriers")

        let removed = try await engine.removeActiveCopy(after: verified)
        XCTAssertTrue([.archivedLocal, .archivedOnlineOnly].contains(removed.state))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        let barriersAfterRemoval = await provider.barrierCount()
        XCTAssertEqual(
            barriersAfterRemoval, barriersAfterArchive + 1,
            "removal must re-run provider persistence for the exact generation"
        )
        let capabilitiesCalls = await provider.capabilitiesCount()
        XCTAssertGreaterThanOrEqual(capabilitiesCalls, 1, "removal must revalidate capabilities")
    }

    func testRemoveActiveCopyFailsClosedWhenProviderBarrierThrows() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let goodProvider = CountingFaultBarrierProvider(
            durability: .verifiedLocal,
            waitsForDurability: false
        )
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: goodProvider,
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in }
        )
        let verified = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
        let sourceBefore = try fixture.snapshotSource()

        // Swap to a failing provider for the removal attempt only by rebuilding
        // the engine over the same store (same persisted terminal record).
        let failingEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: FailingFaultBarrierProvider(),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in XCTFail("failing barrier must not reach removal admission") }
        )
        do {
            _ = try await failingEngine.removeActiveCopy(after: verified)
            XCTFail("provider barrier failure must block removal")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .durabilityUnavailable)
        }
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore, "Active copy kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: verified.destinationURL.path))
        XCTAssertEqual(try store.record(id: verified.id)?.state, .archiveVerified)
    }

    func testRemoveActiveCopyFailsClosedWhenCapabilitiesMismatch() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: CountingFaultBarrierProvider(
                durability: .verifiedLocal,
                waitsForDurability: false
            ),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in }
        )
        let verified = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)

        // Cloud capabilities (waits=true) with a local-only fresh claim must
        // not authorize deletion; remote backup is never inferred from files.
        let mismatched = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: MismatchedFaultBarrierProvider(),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in XCTFail("mismatched capabilities must not reach admission") }
        )
        do {
            _ = try await mismatched.removeActiveCopy(after: verified)
            XCTFail("capabilities mismatch must block removal")
        } catch {
            XCTAssertEqual(error as? LocalVaultTransferError, .missingPersistedArchiveEvidence)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertEqual(try store.record(id: verified.id)?.state, .archiveVerified)
    }

    func testRemoveActiveCopyFailsClosedWhenJournalProofThrows() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore(proof: .fail(
            VaultTransferPersistenceProofError.unproven("journal barrier failed")
        ))
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: CountingFaultBarrierProvider(
                durability: .verifiedLocal,
                waitsForDurability: false
            ),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in XCTFail("journal failure must not reach removal admission") }
        )
        // Archive itself does not require the journal barrier, so it succeeds
        // even when the store is configured to fail proof; only removal blocks.
        let verified = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
        do {
            _ = try await engine.removeActiveCopy(after: verified)
            XCTFail("journal failure must block destructive admission")
        } catch {
            XCTAssertEqual(
                error as? VaultTransferPersistenceProofError,
                .unproven("journal barrier failed")
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: verified.destinationURL.path))
        // Fresh terminal durability was persisted before the journal barrier,
        // but removal was never authorized.
        let persisted = try XCTUnwrap(store.record(id: verified.id))
        XCTAssertEqual(persisted.state, .archiveVerified)
        XCTAssertEqual(persisted.durability, .verifiedLocal)
    }

    func testSQLiteStoreEnforcesJournalBarrierError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fault-sqlite-journal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let goodURL = root.appendingPathComponent("good.sqlite")
        let goodDB = try SQLiteArchiveDatabase(databaseURL: goodURL)
        let goodStore = try SQLiteVaultTransferStore(database: goodDB)
        XCTAssertNoThrow(try goodStore.proveRecoveryPersistence())

        let failingSeam = SQLiteArchiveDatabase.SQLiteRecoverySyncSeam(
            checkpointMainDatabase: { _ in
                throw SQLiteArchiveDatabase.StoreError.exec("injected checkpoint failure")
            },
            synchronizeFile: { _, _ in
                throw SQLiteArchiveDatabase.StoreError.exec("injected file sync failure")
            },
            synchronizeDirectory: { _, _, _ in
                throw SQLiteArchiveDatabase.StoreError.exec("injected dir sync failure")
            }
        )
        let badDB = try SQLiteArchiveDatabase(
            databaseURL: root.appendingPathComponent("bad.sqlite"),
            recoverySeam: failingSeam
        )
        let badStore = try SQLiteVaultTransferStore(database: badDB)
        XCTAssertThrowsError(try badStore.proveRecoveryPersistence())
        // Default for stores that cannot prove is fail-closed, never silent success.
        let defaultStore = FaultDefaultProofStore()
        XCTAssertThrowsError(try defaultStore.proveRecoveryPersistence()) { error in
            XCTAssertEqual(
                error as? VaultTransferPersistenceProofError,
                .unproven("This store cannot prove recovery persistence. Existing copies were kept.")
            )
        }
    }

    // MARK: - Legacy / mutation

    func testRemoveActiveCopyRejectsCorruptLegacyGeneration() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: CountingFaultBarrierProvider(
                durability: .verifiedLocal,
                waitsForDurability: false
            ),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in XCTFail("corrupt generation must not reach admission") }
        )
        var verified = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
        // Corrupt the exact generation after it verified.
        try Data("corrupt".utf8).write(
            to: verified.destinationURL.appendingPathComponent("Artist Song.cpr"),
            options: .atomic
        )
        // Reload persisted view for the removal call (same id/state).
        verified = try XCTUnwrap(store.record(id: verified.id))
        do {
            _ = try await engine.removeActiveCopy(after: verified)
            XCTFail("corrupt generation must block removal")
        } catch {
            // Either the pre-barrier manifest check or the post-barrier
            // revalidation fails closed; both keep every copy.
            XCTAssertTrue(
                error is VaultManifestError || error as? LocalVaultTransferError == .missingPersistedArchiveEvidence
                || error as? LocalVaultTransferError == .sourceMutated,
                "unexpected error \(error)"
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertEqual(try store.record(id: verified.id)?.state, .archiveVerified)
    }

    func testRemoveActiveCopyRejectsMutationDuringBarrier() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let archiver = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: CountingFaultBarrierProvider(
                durability: .verifiedLocal,
                waitsForDurability: false
            ),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in }
        )
        let verified = try await archiver.archive(projectID: ProjectID(), sourceURL: fixture.source)
        let mutating = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: MutatingFaultBarrierProvider(),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in XCTFail("mutated bytes must not reach admission") }
        )
        do {
            _ = try await mutating.removeActiveCopy(after: verified)
            XCTFail("post-barrier manifest mismatch must block removal")
        } catch {
            XCTAssertTrue(error is VaultManifestError, "expected manifest mismatch, got \(error)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertEqual(try store.record(id: verified.id)?.state, .archiveVerified)
    }

    func testSurvivorRetirementPreservesLastRecoverableWhenUnproven() async throws {
        for caseName in ["missing", "corrupt", "unproven"] {
            let fixture = try FaultFixture()
            defer { fixture.remove() }
            let store = FaultInMemoryStore()
            let projectID = ProjectID()
            let obsoleteID = UUID()
            let obsoleteStaging = fixture.archive
                .appendingPathComponent(".niko-staging", isDirectory: true)
                .appendingPathComponent(projectID.description, isDirectory: true)
                .appendingPathComponent(obsoleteID.uuidString.lowercased(), isDirectory: true)
            try FileManager.default.createDirectory(at: obsoleteStaging, withIntermediateDirectories: true)
            try Data("obsolete staging".utf8).write(to: obsoleteStaging.appendingPathComponent("partial.cpr"))
            var obsolete = VaultTransferRecord(
                id: obsoleteID,
                projectID: projectID,
                sourceURL: fixture.source,
                stagingURL: obsoleteStaging,
                destinationURL: fixture.archive.appendingPathComponent("generations/obsolete"),
                state: .failedRecoverable,
                createdAt: Date(timeIntervalSince1970: 100)
            )
            obsolete.updatedAt = Date(timeIntervalSince1970: 100)
            obsolete.error = VaultTransferError(
                origin: .awaitingProviderDurability,
                reason: .providerUnsynced,
                message: "obsolete"
            )
            try store.save(obsolete)

            let survivorID = UUID()
            let survivorURL = fixture.archive
                .appendingPathComponent("generations", isDirectory: true)
                .appendingPathComponent(projectID.description, isDirectory: true)
                .appendingPathComponent("generation-\(survivorID.uuidString.lowercased())", isDirectory: true)
            try FileManager.default.createDirectory(
                at: survivorURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: fixture.source, to: survivorURL)
            let survivorManifest = try VaultManifestBuilder().build(at: survivorURL)
            // Corrupt after building so verification fails.
            if caseName == "corrupt" {
                try Data("drift".utf8).write(
                    to: survivorURL.appendingPathComponent("Artist Song.cpr"),
                    options: .atomic
                )
            }
            if caseName == "missing" {
                try FileManager.default.removeItem(at: survivorURL)
            }
            // For the unproven case the generation verifies but durability is nil.
            var survivor = VaultTransferRecord(
                id: survivorID,
                projectID: projectID,
                sourceURL: fixture.source,
                stagingURL: fixture.archive.appendingPathComponent(".niko-staging/survivor"),
                destinationURL: survivorURL,
                state: .archiveVerified,
                createdAt: Date(timeIntervalSince1970: 200)
            )
            survivor.updatedAt = Date(timeIntervalSince1970: 200)
            survivor.manifestID = survivorManifest.id
            survivor.manifest = survivorManifest
            survivor.durability = caseName == "unproven" ? nil : .verifiedLocal
            // For corrupt/missing the manifest still describes the original bytes.
            _ = survivorManifest
            try store.save(survivor)

            let engine = try LocalVaultTransferEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                store: store,
                provider: CountingFaultBarrierProvider(
                    durability: .verifiedLocal,
                    waitsForDurability: false
                ),
                writeAdmission: allowFaultWrites
            )
            _ = await engine.recoverAtLaunch()
            let persistedObsolete = try XCTUnwrap(
                store.record(id: obsoleteID),
                "\(caseName)"
            )
            XCTAssertNotEqual(persistedObsolete.state, .superseded, "\(caseName)")
            XCTAssertNil(persistedObsolete.supersededBy, "\(caseName)")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: obsoleteStaging.path),
                "\(caseName): supersession alone must not delete staging"
            )
        }
    }

    func testSurvivorRetirementRunsFreshBarrierPlusFinalBindingAndJournalProof() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let projectID = ProjectID()
        let obsoleteID = UUID()
        let obsoleteStaging = fixture.archive
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent(obsoleteID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: obsoleteStaging, withIntermediateDirectories: true)
        try Data("obsolete staging".utf8).write(to: obsoleteStaging.appendingPathComponent("partial.cpr"))
        var obsolete = VaultTransferRecord(
            id: obsoleteID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: obsoleteStaging,
            destinationURL: fixture.archive.appendingPathComponent("generations/obsolete"),
            state: .failedRecoverable,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        obsolete.updatedAt = Date(timeIntervalSince1970: 100)
        obsolete.error = VaultTransferError(
            origin: .awaitingProviderDurability,
            reason: .providerUnsynced,
            message: "obsolete"
        )
        try store.save(obsolete)

        let survivorID = UUID()
        let survivorURL = fixture.archive
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent("generation-\(survivorID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: survivorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.source, to: survivorURL)
        let survivorManifest = try VaultManifestBuilder().build(at: survivorURL)
        var survivor = VaultTransferRecord(
            id: survivorID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: fixture.archive.appendingPathComponent(".niko-staging/survivor"),
            destinationURL: survivorURL,
            state: .archiveVerified,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        survivor.updatedAt = Date(timeIntervalSince1970: 200)
        survivor.manifestID = survivorManifest.id
        survivor.manifest = survivorManifest
        survivor.durability = .verifiedLocal
        try store.save(survivor)

        let provider = CountingFaultBarrierProvider(
            durability: .verifiedLocal,
            waitsForDurability: false
        )
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowFaultWrites
        )
        let results = await engine.recoverAtLaunch()
        let observedbarrierCount = await provider.barrierCount()
        XCTAssertGreaterThanOrEqual(
            observedbarrierCount, 1,
            "retirement must re-run provider durability over the exact survivor generation"
        )
        let observedcapabilitiesCount = await provider.capabilitiesCount()
        XCTAssertGreaterThanOrEqual(
            observedcapabilitiesCount, 1,
            "retirement must revalidate capabilities honestly"
        )
        let persistedObsolete = try XCTUnwrap(store.record(id: obsoleteID))
        XCTAssertEqual(persistedObsolete.state, .superseded)
        XCTAssertEqual(persistedObsolete.supersededBy, survivorID)
        XCTAssertFalse(results.contains(where: { $0.id == obsoleteID }), "superseded must not replay")
        XCTAssertTrue(FileManager.default.fileExists(atPath: obsoleteStaging.path))
        // Final manifest/path binding still holds after the barrier awaits.
        try VaultManifestBuilder().verifyArchive(survivorManifest, at: survivorURL)
    }

    func testSurvivorRetirementFailsClosedWhenFreshBarrierThrows() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let projectID = ProjectID()
        let obsoleteID = UUID()
        let obsoleteStaging = fixture.archive
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent(obsoleteID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: obsoleteStaging, withIntermediateDirectories: true)
        try Data("obsolete staging".utf8).write(to: obsoleteStaging.appendingPathComponent("partial.cpr"))
        var obsolete = VaultTransferRecord(
            id: obsoleteID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: obsoleteStaging,
            destinationURL: fixture.archive.appendingPathComponent("generations/obsolete"),
            state: .failedRecoverable,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        obsolete.updatedAt = Date(timeIntervalSince1970: 100)
        obsolete.error = VaultTransferError(
            origin: .awaitingProviderDurability,
            reason: .providerUnsynced,
            message: "obsolete"
        )
        try store.save(obsolete)

        let survivorID = UUID()
        let survivorURL = fixture.archive
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent("generation-\(survivorID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: survivorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.source, to: survivorURL)
        let survivorManifest = try VaultManifestBuilder().build(at: survivorURL)
        var survivor = VaultTransferRecord(
            id: survivorID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: fixture.archive.appendingPathComponent(".niko-staging/survivor"),
            destinationURL: survivorURL,
            state: .archiveVerified,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        survivor.updatedAt = Date(timeIntervalSince1970: 200)
        survivor.manifestID = survivorManifest.id
        survivor.manifest = survivorManifest
        survivor.durability = .verifiedLocal
        try store.save(survivor)

        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: FailingFaultBarrierProvider(),
            writeAdmission: allowFaultWrites
        )
        _ = await engine.recoverAtLaunch()
        let persistedObsolete = try XCTUnwrap(store.record(id: obsoleteID))
        XCTAssertNotEqual(persistedObsolete.state, .superseded, "failed reproof leaves recoverable")
        XCTAssertNil(persistedObsolete.supersededBy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: obsoleteStaging.path))
    }

    func testSurvivorRetirementFailsClosedWhenJournalProofThrows() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore(proof: .fail(
            VaultTransferPersistenceProofError.unproven("injected retirement journal failure")
        ))
        let projectID = ProjectID()
        let obsoleteID = UUID()
        let obsoleteStaging = fixture.archive
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent(obsoleteID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: obsoleteStaging, withIntermediateDirectories: true)
        try Data("obsolete staging".utf8).write(to: obsoleteStaging.appendingPathComponent("partial.cpr"))
        var obsolete = VaultTransferRecord(
            id: obsoleteID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: obsoleteStaging,
            destinationURL: fixture.archive.appendingPathComponent("generations/obsolete"),
            state: .failedRecoverable,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        obsolete.updatedAt = Date(timeIntervalSince1970: 100)
        obsolete.error = VaultTransferError(
            origin: .awaitingProviderDurability,
            reason: .providerUnsynced,
            message: "obsolete"
        )
        try store.save(obsolete)

        let survivorID = UUID()
        let survivorURL = fixture.archive
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent("generation-\(survivorID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: survivorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.source, to: survivorURL)
        let survivorManifest = try VaultManifestBuilder().build(at: survivorURL)
        var survivor = VaultTransferRecord(
            id: survivorID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: fixture.archive.appendingPathComponent(".niko-staging/survivor"),
            destinationURL: survivorURL,
            state: .archiveVerified,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        survivor.updatedAt = Date(timeIntervalSince1970: 200)
        survivor.manifestID = survivorManifest.id
        survivor.manifest = survivorManifest
        survivor.durability = .verifiedLocal
        try store.save(survivor)

        let provider = CountingFaultBarrierProvider(
            durability: .verifiedLocal,
            waitsForDurability: false
        )
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowFaultWrites
        )
        _ = await engine.recoverAtLaunch()
        let observedbarrierCount = await provider.barrierCount()
        XCTAssertGreaterThanOrEqual(
            observedbarrierCount, 1,
            "journal is proven only after fresh reproof ran"
        )
        let persistedObsolete = try XCTUnwrap(store.record(id: obsoleteID))
        XCTAssertNotEqual(persistedObsolete.state, .superseded, "journal failure leaves recoverable")
        XCTAssertNil(persistedObsolete.supersededBy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: obsoleteStaging.path))
    }

    func testOnlineOnlySurvivorRetirementNeverMaterializes() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let projectID = ProjectID()
        let obsoleteID = UUID()
        let obsoleteStaging = fixture.archive
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent(obsoleteID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: obsoleteStaging, withIntermediateDirectories: true)
        try Data("obsolete staging".utf8).write(to: obsoleteStaging.appendingPathComponent("partial.cpr"))
        var obsolete = VaultTransferRecord(
            id: obsoleteID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: obsoleteStaging,
            destinationURL: fixture.archive.appendingPathComponent("generations/obsolete"),
            state: .failedRecoverable,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        obsolete.updatedAt = Date(timeIntervalSince1970: 100)
        obsolete.error = VaultTransferError(
            origin: .awaitingProviderDurability,
            reason: .providerUnsynced,
            message: "obsolete"
        )
        try store.save(obsolete)

        let survivorID = UUID()
        let survivorURL = fixture.archive
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent("generation-\(survivorID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: survivorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.source, to: survivorURL)
        // Simulate an online-only placeholder: bytes drift locally, but the
        // manifest still describes the provider-synced generation. Retirement
        // must rely on provider proof, never on placeholder bytes.
        try Data("provider-drift".utf8).write(
            to: survivorURL.appendingPathComponent("Artist Song.cpr"),
            options: .atomic
        )
        let syncedManifest = try VaultManifestBuilder().build(at: fixture.source)
        var survivor = VaultTransferRecord(
            id: survivorID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: fixture.archive.appendingPathComponent(".niko-staging/survivor"),
            destinationURL: survivorURL,
            state: .archivedOnlineOnly,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        survivor.updatedAt = Date(timeIntervalSince1970: 200)
        survivor.manifestID = syncedManifest.id
        survivor.manifest = syncedManifest
        survivor.durability = .syncedToProvider
        try store.save(survivor)

        let provider = OnlineOnlyRetirementProofProvider()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowFaultWrites
        )
        _ = await engine.recoverAtLaunch()
        let observeddurableCalls = await provider.durableCalls()
        XCTAssertEqual(observeddurableCalls, 1, "online-only needs fresh sync proof")
        let observedlocalityCalls = await provider.localityCalls()
        XCTAssertEqual(observedlocalityCalls, 1, "online-only needs live locality")
        let observedmaterializeCalls = await provider.materializeCalls()
        XCTAssertEqual(observedmaterializeCalls, 0, "retirement must never materialize")
        let persistedObsolete = try XCTUnwrap(store.record(id: obsoleteID))
        XCTAssertEqual(persistedObsolete.state, .superseded)
        XCTAssertEqual(persistedObsolete.supersededBy, survivorID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: obsoleteStaging.path))
    }

    // MARK: - Cancellation truthfulness at exact remove boundary

    func testCancellationDuringFreshBarrierKeepsVerifiedSource() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let archiver = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: CountingFaultBarrierProvider(
                durability: .verifiedLocal,
                waitsForDurability: false
            ),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in }
        )
        let verified = try await archiver.archive(projectID: ProjectID(), sourceURL: fixture.source)
        let sourceBefore = try fixture.snapshotSource()
        let gate = FaultBarrierGate()
        let blockingEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: BlockingFaultBarrierProvider(gate: gate),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in XCTFail("cancelled barrier must not reach admission") }
        )
        let task = Task { try await blockingEngine.removeActiveCopy(after: verified) }
        await gate.waitForEntry()
        task.cancel()
        await gate.release()
        do {
            _ = try await task.value
            XCTFail("cancellation during fresh barrier must propagate")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        XCTAssertEqual(try store.record(id: verified.id)?.state, .archiveVerified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: verified.destinationURL.path))
    }

    // MARK: - Restart / concurrency / capacity

    func testRestartFromPersistedIntermediatePhasesNeverAutoDeletes() async throws {
        for phase in [
            VaultTransferState.copyingToArchiveStaging,
            VaultTransferState.verifyingArchiveStaging,
            VaultTransferState.awaitingProviderDurability,
            VaultTransferState.promotingArchiveGeneration,
        ] {
            let fixture = try FaultFixture()
            defer { fixture.remove() }
            let store = FaultInMemoryStore()
            let projectID = ProjectID()
            let transferID = UUID()
            let staging = fixture.archive
                .appendingPathComponent(".niko-staging", isDirectory: true)
                .appendingPathComponent(projectID.description, isDirectory: true)
                .appendingPathComponent(transferID.uuidString.lowercased(), isDirectory: true)
            try FileManager.default.createDirectory(
                at: staging.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: fixture.source, to: staging)
            let manifest = try VaultManifestBuilder().build(at: staging)
            var record = VaultTransferRecord(
                id: transferID,
                projectID: projectID,
                sourceURL: fixture.source,
                stagingURL: staging,
                destinationURL: fixture.archive
                    .appendingPathComponent("generations", isDirectory: true)
                    .appendingPathComponent(projectID.description, isDirectory: true)
                    .appendingPathComponent("generation-\(transferID.uuidString.lowercased())", isDirectory: true),
                state: phase,
                createdAt: Date(timeIntervalSince1970: 100)
            )
            record.updatedAt = Date(timeIntervalSince1970: 100)
            // Verifying and later phases carry a manifest; copying rebuilds it.
            if phase != .copyingToArchiveStaging {
                record.manifestID = manifest.id
                record.manifest = manifest
                record.totalBytes = manifest.totalBytes
                record.completedBytes = manifest.totalBytes
            }
            try store.save(record)
            let engine = try LocalVaultTransferEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                store: store,
                provider: CountingFaultBarrierProvider(
                    durability: .verifiedLocal,
                    waitsForDurability: false
                ),
                writeAdmission: allowFaultWrites,
                removalAdmission: { _ in XCTFail("restart must not auto-delete Active") }
            )
            let results = await engine.recoverAtLaunch()
            XCTAssertEqual(results.count, 1, "\(phase)")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: fixture.source.path),
                "\(phase): relaunch must never auto-delete Active"
            )
            // Staging or the promoted generation must still exist for review.
            let stagingExists = FileManager.default.fileExists(atPath: staging.path)
            let generationExists = FileManager.default.fileExists(
                atPath: record.destinationURL.path
            )
            XCTAssertTrue(stagingExists || generationExists, "\(phase)")
        }
    }

    func testConcurrentClaimsKeepSingleOwner() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: CountingFaultBarrierProvider(
                durability: .verifiedLocal,
                waitsForDurability: false
            ),
            writeAdmission: allowFaultWrites
        )
        let projectID = ProjectID()
        let firstTask = Task { try await engine.archive(projectID: projectID, sourceURL: fixture.source) }
        let secondTask = Task { try await engine.archive(projectID: projectID, sourceURL: fixture.source) }
        let firstResult = try? await firstTask.value
        let secondResult = try? await secondTask.value
        let successes = [firstResult, secondResult].compactMap { $0 }.count
        // Exactly one transfer owns the project; the store holds one record.
        // The loser throws transferAlreadyOwned (or fails closed on occupied
        // staging); either way only one generation may exist and Active stays.
        let records = try store.allTransferRecords().filter { $0.projectID == projectID }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(successes, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    func testWriteAdmissionCapacityPostponementFailsClosedKeepingActive() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: { _, _ in
                throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
            }
        )
        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("capacity postponement must fail the copy before any bytes move")
        } catch {
            XCTAssertEqual(
                error as? VaultWriteAdmissionError,
                .postponed(.insufficientArchiveCapacity)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
        let records = try store.allTransferRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: records.first?.destinationURL.path ?? ""))
    }

    func testMidCopyPOSIXENOSPCAfterPartialBytesFailsClosedKeepingActive() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let sourceBefore = try fixture.snapshotSource()
        let store = FaultInMemoryStore()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            fileManager: ENOSPCMidCopyFileManager(),
            writeAdmission: allowFaultWrites
        )
        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("mid-copy POSIX ENOSPC must fail the copy")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSPOSIXErrorDomain)
            XCTAssertEqual(nsError.code, Int(ENOSPC))
        }
        // Source intact; partial staging was written but never verified or
        // promoted; the persisted failure is truthful about capacity.
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        let record = try XCTUnwrap(store.allTransferRecords().first)
        XCTAssertEqual(record.state, .failedRecoverable)
        XCTAssertEqual(record.error?.origin, .copyingToArchiveStaging)
        XCTAssertEqual(record.error?.reason, .insufficientSpace)
        XCTAssertGreaterThan(record.retryCount, 0)
        XCTAssertNotNil(record.nextRetryAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.destinationURL.path))
        // The bulk copy threw before any manifest was persisted, so the
        // partial tree was never verified: a missing manifest is itself proof
        // no verified generation exists.
        XCTAssertNil(record.manifest)
        XCTAssertNil(record.durability)
        // Relaunch stays truthful: the persisted failure still requires write
        // admission and still keeps the Active copy; it never auto-deletes.
        let relaunch = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            fileManager: ENOSPCMidCopyFileManager(),
            writeAdmission: allowFaultWrites
        )
        _ = await relaunch.recoverAtLaunch()
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    func testFlushBarrierENOSPCFailsClosedKeepingActive() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let sourceBefore = try fixture.snapshotSource()
        let store = FaultInMemoryStore()
        var seam = LocalVaultFlushSeam.live
        seam.synchronize = { _, url, _ in
            throw LocalVaultDurabilityBarrierError.fileFlushFailed(url, errno: ENOSPC)
        }
        let provider = LocalFolderArchiveStorage(
            root: fixture.archive,
            fileManager: .default,
            flushSeam: seam
        )
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowFaultWrites
        )
        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("flush-seam ENOSPC must fail durability")
        } catch {
            guard case LocalVaultDurabilityBarrierError.fileFlushFailed(_, let errno) = error else {
                XCTFail("expected fileFlushFailed ENOSPC, got \(error)")
                return
            }
            XCTAssertEqual(errno, ENOSPC)
        }
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        let record = try XCTUnwrap(store.allTransferRecords().first)
        XCTAssertEqual(record.state, .failedRecoverable)
        XCTAssertEqual(record.error?.reason, .insufficientSpace)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.destinationURL.path))
    }

    func testDestinationDisappearsAfterCopyFailsClosedKeepingActive() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let sourceBefore = try fixture.snapshotSource()
        let store = FaultInMemoryStore()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: DeletingFaultBarrierProvider(),
            writeAdmission: allowFaultWrites
        )
        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("disappearing destination must fail the transfer")
        } catch {}
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        let record = try XCTUnwrap(store.allTransferRecords().first)
        XCTAssertNotEqual(record.state, .archiveVerified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
        // The partial generation was never verified; no terminal durability
        // claim exists.
        XCTAssertNil(record.durability)
    }

    func testDestinationDisappearsBeforeRemovalKeepsSourceAndBlocksDeletion() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let archiver = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: CountingFaultBarrierProvider(
                durability: .verifiedLocal,
                waitsForDurability: false
            ),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in }
        )
        let verified = try await archiver.archive(projectID: ProjectID(), sourceURL: fixture.source)
        let sourceBefore = try fixture.snapshotSource()
        try FileManager.default.removeItem(at: verified.destinationURL)
        let remover = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: CountingFaultBarrierProvider(
                durability: .verifiedLocal,
                waitsForDurability: false
            ),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in XCTFail("missing generation must not reach admission") }
        )
        do {
            _ = try await remover.removeActiveCopy(after: verified)
            XCTFail("missing generation must block removal")
        } catch {}
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        XCTAssertEqual(try store.record(id: verified.id)?.state, .archiveVerified)
    }

    func testJournalSaveFailureDuringRemovalKeepsSourceAndVerifiedGeneration() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let backing = FaultInMemoryStore()
        let archiver = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: backing,
            provider: CountingFaultBarrierProvider(
                durability: .verifiedLocal,
                waitsForDurability: false
            ),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in }
        )
        let verified = try await archiver.archive(projectID: ProjectID(), sourceURL: fixture.source)
        let sourceBefore = try fixture.snapshotSource()
        // Fail the next save (the fresh-durability persist inside removal)
        // without touching the already-persisted verified generation.
        let failingStore = FailingSaveFaultStore(wrapping: backing, failNextSaves: 1)
        let remover = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: failingStore,
            provider: CountingFaultBarrierProvider(
                durability: .verifiedLocal,
                waitsForDurability: false
            ),
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in XCTFail("journal save failure must block admission") }
        )
        do {
            _ = try await remover.removeActiveCopy(after: verified)
            XCTFail("journal save failure must block removal")
        } catch {}
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        // The already-persisted verified generation remains accessible: exact
        // manifest bytes still verify at the destination.
        try VaultManifestBuilder().verifyArchive(
            try XCTUnwrap(verified.manifest),
            at: verified.destinationURL
        )
        XCTAssertEqual(try backing.record(id: verified.id)?.state, .archiveVerified)
    }

    // MARK: - Live syscalls (separate from simulated faults)

    func testLiveLocalBarrierOnTempStorageProvesVerifiedLocal() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let storage = LocalFolderArchiveStorage(root: fixture.archive)
        let generation = fixture.archive
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent("live-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        try Data("live".utf8).write(to: generation.appendingPathComponent("Artist Song.cpr"))
        let durability = try await storage.waitUntilDurable(generation)
        XCTAssertEqual(durability, .verifiedLocal)
        // Live proof is syscall acceptance on temp storage, not a power-cut claim.
        XCTAssertTrue(FileManager.default.fileExists(atPath: generation.path))
    }
}

// MARK: - Fault fixtures (UUID-only, disposable temp dirs)

private struct FaultFixture {
    let root: URL
    let active: URL
    let archive: URL
    let source: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-durability-fault-\(UUID().uuidString)", isDirectory: true)
        active = root.appendingPathComponent("Active", isDirectory: true)
        archive = root.appendingPathComponent("Archive", isDirectory: true)
        source = active.appendingPathComponent("Artist Song", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("Audio", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("cubase-project".utf8).write(to: source.appendingPathComponent("Artist Song.cpr"))
        try Data((0..<1024).map { UInt8($0 % 251) }).write(
            to: source.appendingPathComponent("Audio/take.wav")
        )
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
    }

    func snapshotSource() throws -> [String: Data] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: Array(keys))
        var result: [String: Data] = [:]
        while let url = enumerator?.nextObject() as? URL {
            if try url.resourceValues(forKeys: keys).isRegularFile == true {
                result[String(url.path.dropFirst(source.path.count + 1))] = try Data(contentsOf: url)
            }
        }
        return result
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private let allowFaultWrites: LocalVaultTransferEngine.WriteAdmission = { _, operation in
    try await operation()
}

/// In-memory store with explicit deterministic proof semantics. Production
/// SQLite enforces the real journal barrier; this fake never silently claims
/// success unless constructed with `.succeed`.
private final class FaultInMemoryStore: VaultTransferStoring, @unchecked Sendable {
    enum Proof: Sendable {
        case succeed
        case fail(Error)
    }

    private let lock = NSLock()
    private var records: [UUID: VaultTransferRecord] = [:]
    private var proof: Proof

    init(proof: Proof = .succeed) { self.proof = proof }

    func setProof(_ proof: Proof) { lock.withLock { self.proof = proof } }

    func save(_ record: VaultTransferRecord) throws {
        lock.withLock { records[record.id] = record }
    }

    func claimTransfer(_ record: VaultTransferRecord) throws -> VaultTransferClaimResult {
        lock.withLock {
            let source = record.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path
            let destination = record.destinationURL.standardizedFileURL.resolvingSymlinksInPath().path
            if let existing = records.values.first(where: {
                VaultTransferOwnershipPolicy.ownsProject($0.state)
                    && ($0.projectID == record.projectID
                        || $0.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path == source
                        || $0.destinationURL.standardizedFileURL.resolvingSymlinksInPath().path == destination)
            }) {
                return .existing(existing)
            }
            records[record.id] = record
            return .claimed(record)
        }
    }

    func record(id: UUID) throws -> VaultTransferRecord? {
        lock.withLock { records[id] }
    }

    func recoverableRecords() throws -> [VaultTransferRecord] {
        let terminal: Set<VaultTransferState> = [
            .archiveVerified, .archivedLocal, .archivedOnlineOnly,
            .readyLocal, .openingInCubase, .recoveryRequired, .superseded,
        ]
        return lock.withLock { records.values.filter { !terminal.contains($0.state) } }
    }

    func allTransferRecords() throws -> [VaultTransferRecord] {
        lock.withLock { Array(records.values) }
    }

    func proveRecoveryPersistence() throws {
        switch lock.withLock({ proof }) {
        case .succeed:
            return
        case .fail(let error):
            throw error
        }
    }
}

private struct FaultDefaultProofStore: VaultTransferStoring {
    func save(_ record: VaultTransferRecord) throws {}
    func record(id: UUID) throws -> VaultTransferRecord? { nil }
    func recoverableRecords() throws -> [VaultTransferRecord] { [] }
    func allTransferRecords() throws -> [VaultTransferRecord] { [] }
}

private actor CountingFaultBarrierProvider: ArchiveStorageProvider {
    private let durability: VaultDurability
    private let waits: Bool
    private var barriers = 0
    private var capabilitiesCalls = 0

    init(durability: VaultDurability, waitsForDurability: Bool) {
        self.durability = durability
        self.waits = waitsForDurability
    }

    func capabilities() async throws -> StorageCapabilities {
        capabilitiesCalls += 1
        return .init(
            waitsForDurability: waits,
            supportsMaterialization: false,
            supportsEviction: false
        )
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        barriers += 1
        return durability
    }

    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
    func barrierCount() -> Int { barriers }
    func capabilitiesCount() -> Int { capabilitiesCalls }
}

private struct FailingFaultBarrierProvider: ArchiveStorageProvider {
    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: true, supportsMaterialization: true, supportsEviction: true)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        throw FileProviderArchiveStorageError.durabilityUnavailable
    }

    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

private struct MismatchedFaultBarrierProvider: ArchiveStorageProvider {
    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: true, supportsMaterialization: true, supportsEviction: true)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

private struct MutatingFaultBarrierProvider: ArchiveStorageProvider {
    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: false, supportsEviction: false)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        try Data("mutated-while-waiting".utf8).write(
            to: location.appendingPathComponent("Artist Song.cpr"),
            options: .atomic
        )
        return .verifiedLocal
    }

    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

private actor FaultBarrierGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func signalEntry() {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor BlockingFaultBarrierProvider: ArchiveStorageProvider {
    private let gate: FaultBarrierGate

    init(gate: FaultBarrierGate) { self.gate = gate }

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: false, supportsEviction: false)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        await gate.signalEntry()
        await gate.waitForRelease()
        try Task.checkCancellation()
        return .verifiedLocal
    }

    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

/// Deterministic POSIX ENOSPC mid-copy: writes partial fixture bytes into the
/// staging destination, then throws ENOSPC without completing the copy. No
/// real disk exhaustion is required.
private final class ENOSPCMidCopyFileManager: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        var isDirectory: ObjCBool = false
        if fileExists(atPath: srcURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            try createDirectory(at: dstURL, withIntermediateDirectories: true)
            let cprSource = srcURL.appendingPathComponent("Artist Song.cpr")
            if fileExists(atPath: cprSource.path) {
                try super.copyItem(
                    at: cprSource,
                    to: dstURL.appendingPathComponent("Artist Song.cpr")
                )
            }
            let wavSource = srcURL.appendingPathComponent("Audio/take.wav")
            if fileExists(atPath: wavSource.path) {
                try createDirectory(
                    at: dstURL.appendingPathComponent("Audio"),
                    withIntermediateDirectories: true
                )
                let full = try Data(contentsOf: wavSource)
                try full.prefix(max(1, full.count / 2)).write(
                    to: dstURL.appendingPathComponent("Audio/take.wav")
                )
            }
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(ENOSPC),
                userInfo: [NSLocalizedDescriptionKey: "No space left on device (injected mid-copy ENOSPC)"]
            )
        }
        try super.copyItem(at: srcURL, to: dstURL)
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(ENOSPC),
            userInfo: [NSLocalizedDescriptionKey: "No space left on device (injected mid-copy ENOSPC)"]
        )
    }
}

private struct DeletingFaultBarrierProvider: ArchiveStorageProvider {
    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: false, supportsEviction: false)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        try? FileManager.default.removeItem(at: location)
        throw LocalVaultDurabilityBarrierError.missingNode(location)
    }

    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

/// Cloud retirement proof without materializing: fresh sync plus live
/// locality, counting each so tests prove no silent materialization.
private actor OnlineOnlyRetirementProofProvider: ArchiveStorageProvider {
    private var durables = 0
    private var localities = 0
    private var materializes = 0

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: true, supportsMaterialization: true, supportsEviction: true)
    }

    func currentLocality(at location: URL, manifest: VaultManifest) async throws -> ArchiveStorageLocality {
        localities += 1
        return .materializationRequired
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        durables += 1
        return .syncedToProvider
    }

    func materialize(_ location: URL) async throws {
        materializes += 1
    }

    func materialize(_ location: URL, manifest: VaultManifest) async throws {
        materializes += 1
    }

    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
    func durableCalls() -> Int { durables }
    func localityCalls() -> Int { localities }
    func materializeCalls() -> Int { materializes }
}

/// Store wrapper that fails a bounded number of saves to model journal/write
/// failures (distinct from `proveRecoveryPersistence` proof errors).
private final class FailingSaveFaultStore: VaultTransferStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let backing: FaultInMemoryStore
    private var remainingFailures: Int

    init(wrapping backing: FaultInMemoryStore, failNextSaves: Int) {
        self.backing = backing
        self.remainingFailures = failNextSaves
    }

    func save(_ record: VaultTransferRecord) throws {
        let shouldFail = lock.withLock { () -> Bool in
            guard remainingFailures > 0 else { return false }
            remainingFailures -= 1
            return true
        }
        if shouldFail {
            throw VaultTransferPersistenceProofError.unproven("injected journal save failure")
        }
        try backing.save(record)
    }

    func claimTransfer(_ record: VaultTransferRecord) throws -> VaultTransferClaimResult {
        try backing.claimTransfer(record)
    }

    func record(id: UUID) throws -> VaultTransferRecord? {
        try backing.record(id: id)
    }

    func recoverableRecords() throws -> [VaultTransferRecord] {
        try backing.recoverableRecords()
    }

    func allTransferRecords() throws -> [VaultTransferRecord] {
        try backing.allTransferRecords()
    }

    func proveRecoveryPersistence() throws {
        try backing.proveRecoveryPersistence()
    }
}
