import Darwin
import Foundation
import SQLite3
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

    func testCatalogReplacementDuringRemovalAdmissionBlockedBySecondProof() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let databaseURL = fixture.root.appendingPathComponent("catalog.sqlite")
        // Explicit init so the raw diagnostic runs on the SAME live connection
        // the engine validates through.
        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let store = try SQLiteVaultTransferStore(database: database)
        let provider = CountingFaultBarrierProvider(
            durability: .verifiedLocal,
            waitsForDurability: false
        )
        let archiver = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in }
        )
        let verified = try await archiver.archive(projectID: ProjectID(), sourceURL: fixture.source)
        let sourceBefore = try fixture.snapshotSource()
        let replacementScratch = fixture.root.appendingPathComponent("replacement.sqlite")
        try makeCatalogReplacementFixture(at: replacementScratch, marker: "replacement-same-path")
        XCTAssertNoThrow(try store.proveRecoveryPersistence(), "first barrier must prove before admission window")
        let divergence = CatalogDivergenceBox()
        let remover = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowFaultWrites,
            removalAdmission: { record in
                let admissionIndex = await divergence.nextAdmission()
                if admissionIndex == 1 {
                    // FIRST admission: read-only probe, no mutation and NO
                    // reopen. Opening/migrating the replacement inside the
                    // callback is interference, and the engine calls admission
                    // twice so replacing here would double-replace.
                    let sees: Bool
                    let readError: String?
                    do {
                        sees = try store.record(id: record.id) != nil
                        readError = nil
                    } catch {
                        sees = false
                        readError = "\(error)"
                    }
                    let raw = rawCatalogConnectionDiagnostic(on: database)
                    await divergence.captureFirst(
                        oldSees: sees,
                        readError: readError,
                        rawStep: raw.step,
                        rawMessage: raw.message
                    )
                    return
                }
                // LAST/second admission only, one-shot. Any further admissions
                // observe the already-replaced pathname without mutating again.
                guard await divergence.tryClaimReplacement() else { return }
                // One-shot actual same-path replacement during the admission
                // await window: rename old main/WAL/SHM fixture-side (inode
                // preserved) while the live connection keeps the old inode
                // open, then copy the fixture main file to the same pathname
                // (new inode, identical sqlite3_db_filename string).
                try replaceCatalogFileAtPath(databaseURL, withFixture: replacementScratch)
                // Post-replacement read through the SAME old connection, still
                // no reopen: the reopen is deferred until the engine returns.
                let postSees: Bool
                let postError: String?
                do {
                    postSees = try store.record(id: record.id) != nil
                    postError = nil
                } catch {
                    postSees = false
                    postError = "\(error)"
                }
                let postRaw = rawCatalogConnectionDiagnostic(on: database)
                await divergence.capturePost(
                    oldSees: postSees,
                    readError: postError,
                    rawStep: postRaw.step,
                    rawMessage: postRaw.message
                )
            }
        )
        do {
            _ = try await remover.removeActiveCopy(after: verified)
            XCTFail("catalog replacement during admission must block Active removal")
        } catch {
            let message = "\(error)"
            XCTAssertTrue(
                message.contains("replaced") || message.contains("binding")
                    || message.contains("moved") || message.contains("identity")
                    || message.contains("changed") || error is SQLiteArchiveDatabase.StoreError,
                "second proof must fail closed on replacement, got \(error)"
            )
        }
        // Deferred reopen: only now bind the replacement pathname, after the
        // engine has returned. No open/migrate happened inside the callback.
        let observed = await divergence.snapshot()
        XCTAssertGreaterThanOrEqual(
            observed.admissions, 2,
            "engine calls removal admission twice; replacement is armed for the second/last admission (got \(observed.admissions))"
        )
        XCTAssertTrue(observed.didReplace, "one-shot replacement must have run on the second admission")
        XCTAssertTrue(
            observed.firstOldSees == true,
            "first admission (pre-replacement, no reopen) must see the record; first readError=\(observed.firstReadError ?? "nil") rawStep=\(observed.firstRawStep.map { "\($0)" } ?? "nil") rawMessage=\(observed.firstRawMessage ?? "nil")"
        )
        // Post-replacement old-connection outcome is platform-dependent and is
        // preserved as diagnostic, not as a causal claim: if the old inode
        // still serves the row, validation alone would have passed and deleted
        // without the second proof (causal protection proven). If SQLite itself
        // refuses the old read (postOldSees false plus non-ROW step or
        // readError), the engine still must fail closed, but do not claim
        // validation-alone-would-delete on this platform. The injected-failure
        // test below is the writable-store proof that the second proof alone
        // blocks deletion.
        if observed.postOldSees != true {
            XCTAssertNotNil(
                observed.postOldSees,
                "post-replacement diagnostic must have been captured (admissions=\(observed.admissions) rawStep=\(observed.postRawStep.map { "\($0)" } ?? "nil") msg=\(observed.postRawMessage ?? "nil") readError=\(observed.postReadError ?? "nil"))"
            )
        }
        let reopenedDB = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let reopenedStore = try SQLiteVaultTransferStore(database: reopenedDB)
        let newSees = (try? reopenedStore.record(id: verified.id)) != nil
        XCTAssertFalse(
            newSees,
            "reopened replacement must not contain the original record (raw post step=\(observed.postRawStep.map { "\($0)" } ?? "nil") msg=\(observed.postRawMessage ?? "nil") readError=\(observed.postReadError ?? "nil"))"
        )
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore, "Active bytes intact")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path), "Active copy kept")
        try VaultManifestBuilder().verifyArchive(
            try XCTUnwrap(verified.manifest),
            at: verified.destinationURL
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: verified.destinationURL.path),
            "verified generation kept"
        )
        let finalReopened = try SQLiteVaultTransferStore(
            database: SQLiteArchiveDatabase(databaseURL: databaseURL)
        )
        XCTAssertNil(try finalReopened.record(id: verified.id), "replacement catalog must not contain original recovery record")
        XCTAssertEqual(
            try catalogReplacementMarker(on: SQLiteArchiveDatabase(databaseURL: databaseURL)),
            "replacement-same-path",
            "pathname must now name the replacement fixture"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: databaseURL.path + ".preReplacement-backup"),
            "old DB bytes/inode preserved fixture-side via rename, not destructive unlink"
        )
        // No recoveryRequired assertion here: the catalog itself was replaced,
        // so the post-admission write may fail. The guaranteed contract is
        // intact Active + verified generation + truthful second-proof error
        // (asserted above). recoveryRequired persistence is asserted only where
        // the store remains writable (see testSecondProofAfterAdmissionBlocksRemovalWhenInjectedToFail).
        _ = try? store.record(id: verified.id)
    }

    func testSecondProofAfterAdmissionBlocksRemovalWhenInjectedToFail() async throws {
        let fixture = try FaultFixture()
        defer { fixture.remove() }
        let store = FaultInMemoryStore()
        let provider = CountingFaultBarrierProvider(
            durability: .verifiedLocal,
            waitsForDurability: false
        )
        let archiver = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in }
        )
        let verified = try await archiver.archive(projectID: ProjectID(), sourceURL: fixture.source)
        let sourceBefore = try fixture.snapshotSource()
        // First barrier already proved inside removeActiveCopy before admission.
        // Flip proof to fail inside the admission await window so only the
        // second (post-admission) proof observes the failure. Without that
        // second proof the removal would succeed and delete Active.
        let remover = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowFaultWrites,
            removalAdmission: { _ in
                store.setProof(.fail(VaultTransferPersistenceProofError.unproven("injected second proof failure")))
            }
        )
        do {
            _ = try await remover.removeActiveCopy(after: verified)
            XCTFail("injected second-proof failure must block Active removal")
        } catch {
            XCTAssertEqual(
                error as? VaultTransferPersistenceProofError,
                .unproven("injected second proof failure")
            )
        }
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore, "Active bytes intact")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path), "Active copy kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: verified.destinationURL.path), "archive generation kept")
        try VaultManifestBuilder().verifyArchive(
            try XCTUnwrap(verified.manifest),
            at: verified.destinationURL
        )
        let persisted = try XCTUnwrap(store.record(id: verified.id))
        XCTAssertEqual(persisted.state, .recoveryRequired, "post-admission proof failure must stay truthfully recoverable")
        XCTAssertEqual(persisted.error?.origin, .removingActiveCopy)
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

private actor CatalogDivergenceBox {
    private var admissions = 0
    private var didReplace = false
    private var firstOldSees: Bool?
    private var firstReadError: String?
    private var firstRawStep: Int32?
    private var firstRawMessage: String?
    private var postOldSees: Bool?
    private var postReadError: String?
    private var postRawStep: Int32?
    private var postRawMessage: String?

    func nextAdmission() -> Int {
        admissions += 1
        return admissions
    }

    func admissionCount() -> Int { admissions }

    func tryClaimReplacement() -> Bool {
        guard !didReplace else { return false }
        didReplace = true
        return true
    }

    func didPerformReplacement() -> Bool { didReplace }

    func captureFirst(oldSees: Bool, readError: String?, rawStep: Int32, rawMessage: String) {
        guard firstOldSees == nil else { return }
        firstOldSees = oldSees
        firstReadError = readError
        firstRawStep = rawStep
        firstRawMessage = rawMessage
    }

    func capturePost(oldSees: Bool, readError: String?, rawStep: Int32, rawMessage: String) {
        guard postOldSees == nil else { return }
        postOldSees = oldSees
        postReadError = readError
        postRawStep = rawStep
        postRawMessage = rawMessage
    }

    func snapshot() -> (
        admissions: Int,
        didReplace: Bool,
        firstOldSees: Bool?,
        firstReadError: String?,
        firstRawStep: Int32?,
        firstRawMessage: String?,
        postOldSees: Bool?,
        postReadError: String?,
        postRawStep: Int32?,
        postRawMessage: String?
    ) {
        (
            admissions,
            didReplace,
            firstOldSees,
            firstReadError,
            firstRawStep,
            firstRawMessage,
            postOldSees,
            postReadError,
            postRawStep,
            postRawMessage
        )
    }
}

private enum CatalogReplacementFixtureError: Error {
    case unreadable(String)
}

/// Different valid SQLite fixture for actual same-path replacement faults.
/// Checkpointed (TRUNCATE) so the main file alone carries the marker; copying
/// only the main file yields a readable replacement. Mirrors
/// LocalVaultDurabilityTests helper semantics near line 1170.
private func makeCatalogReplacementFixture(at url: URL, marker: String) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
        throw CatalogReplacementFixtureError.unreadable("open replacement fixture \(url.path)")
    }
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK else {
        throw CatalogReplacementFixtureError.unreadable("replacement WAL \(url.path)")
    }
    let sanitized = marker.replacingOccurrences(of: "'", with: "")
    let sql = "CREATE TABLE IF NOT EXISTS replacement_probe(marker TEXT); DELETE FROM replacement_probe; INSERT INTO replacement_probe VALUES('\(sanitized)');"
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
        throw CatalogReplacementFixtureError.unreadable("replacement content \(url.path)")
    }
    var checkpoint: OpaquePointer?
    defer { sqlite3_finalize(checkpoint) }
    guard sqlite3_prepare_v2(db, "PRAGMA wal_checkpoint(TRUNCATE);", -1, &checkpoint, nil) == SQLITE_OK,
          sqlite3_step(checkpoint) == SQLITE_ROW else {
        throw CatalogReplacementFixtureError.unreadable("replacement checkpoint \(url.path)")
    }
}

/// Actual same-path replacement: preserve the old main/WAL/SHM fixture-side
/// via rename (no destructive unlink of the live bytes) while the original
/// connection stays open to the old inode, then copy the fixture main file to
/// the same pathname (new inode, identical sqlite3_db_filename string).
/// Backups live next to the target inside the disposable fixture root.
private func replaceCatalogFileAtPath(_ target: URL, withFixture fixture: URL) throws {
    let fm = FileManager.default
    let mainBackup = target.path + ".preReplacement-backup"
    let walBackup = target.path + "-wal.preReplacement-backup"
    let shmBackup = target.path + "-shm.preReplacement-backup"
    try? fm.removeItem(atPath: mainBackup)
    try? fm.removeItem(atPath: walBackup)
    try? fm.removeItem(atPath: shmBackup)
    if fm.fileExists(atPath: target.path) {
        // Rename preserves the inode for forensics; only fall back to unlink
        // if the rename itself fails.
        do {
            try fm.moveItem(atPath: target.path, toPath: mainBackup)
        } catch {
            try fm.removeItem(at: target)
        }
    }
    if fm.fileExists(atPath: target.path + "-wal") {
        do {
            try fm.moveItem(atPath: target.path + "-wal", toPath: walBackup)
        } catch {
            try? fm.removeItem(atPath: target.path + "-wal")
        }
    }
    if fm.fileExists(atPath: target.path + "-shm") {
        do {
            try fm.moveItem(atPath: target.path + "-shm", toPath: shmBackup)
        } catch {
            try? fm.removeItem(atPath: target.path + "-shm")
        }
    }
    // Defensive: no stale WAL/SHM may shadow the replacement main file.
    try? fm.removeItem(atPath: target.path + "-wal")
    try? fm.removeItem(atPath: target.path + "-shm")
    try fm.copyItem(at: fixture, to: target)
}

/// Raw SQLite diagnostic on the SAME live connection the engine validates
/// through. `store.record` hides sqlite3_step non-ROW as nil/empty, so this
/// preserves the raw step code plus errmsg to distinguish "empty" from
/// "read error" after the pathname is rebound.
private func rawCatalogConnectionDiagnostic(on database: SQLiteArchiveDatabase) -> (step: Int32, message: String) {
    do {
        return try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let prepare = sqlite3_prepare_v2(db, "SELECT count(*) FROM sqlite_master;", -1, &statement, nil)
            guard prepare == SQLITE_OK, let statement else {
                let message: String
                if let raw = sqlite3_errmsg(db) {
                    message = String(cString: raw)
                } else {
                    message = "prepare failed"
                }
                return (prepare, message)
            }
            let step = sqlite3_step(statement)
            let message: String
            if let raw = sqlite3_errmsg(db) {
                message = String(cString: raw)
            } else {
                message = "unknown"
            }
            return (step, message)
        }
    } catch {
        return (-1, "\(error)")
    }
}

private func catalogReplacementMarker(on database: SQLiteArchiveDatabase) throws -> String {
    try database.withConnection { db in
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT marker FROM replacement_probe LIMIT 1;", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0) else {
            throw CatalogReplacementFixtureError.unreadable("replacement_probe")
        }
        return String(cString: cString)
    }
}
