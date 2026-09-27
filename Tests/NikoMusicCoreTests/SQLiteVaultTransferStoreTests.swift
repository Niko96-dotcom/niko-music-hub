import Foundation
import SQLite3
import XCTest
@testable import NikoMusicCore

final class SQLiteVaultTransferStoreTests: XCTestCase {
    func testIndependentStoresAtomicallyClaimOneTransfer() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("vault.sqlite")
        let firstStore = try SQLiteVaultTransferStore(
            database: SQLiteArchiveDatabase(databaseURL: databaseURL)
        )
        let secondStore = try SQLiteVaultTransferStore(
            database: SQLiteArchiveDatabase(databaseURL: databaseURL)
        )
        let projectID = ProjectID()
        let makeCandidate = { (id: UUID) in
            VaultTransferRecord(
                id: id,
                projectID: projectID,
                sourceURL: root.appendingPathComponent("active/project"),
                stagingURL: root.appendingPathComponent("archive/.niko-staging/\(id.uuidString)"),
                destinationURL: root.appendingPathComponent("archive/generations/project"),
                state: .activeLocal,
                createdAt: Date(timeIntervalSince1970: 100)
            )
        }
        let firstCandidate = makeCandidate(UUID())
        let secondCandidate = makeCandidate(UUID())

        async let first = Task.detached { try firstStore.claimTransfer(firstCandidate) }.value
        async let second = Task.detached { try secondStore.claimTransfer(secondCandidate) }.value
        let results = try await [first, second]

        XCTAssertEqual(results.filter(\.isClaimed).count, 1)
        XCTAssertEqual(results.filter(\.isExisting).count, 1)
        XCTAssertEqual(try firstStore.allTransferRecords().count, 1)
    }

    func testIndependentStoresAtomicallyClaimOneIncompleteRestore() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("vault.sqlite")
        let firstStore = try SQLiteVaultTransferStore(
            database: SQLiteArchiveDatabase(databaseURL: databaseURL)
        )
        let secondStore = try SQLiteVaultTransferStore(
            database: SQLiteArchiveDatabase(databaseURL: databaseURL)
        )
        let projectID = ProjectID()
        let manifest = VaultManifest(entries: [])
        let makeCandidate = { (id: UUID) in
            VaultRestoreRecord(
                id: id,
                projectID: projectID,
                archiveGenerationURL: root.appendingPathComponent("archive/generations/project"),
                stagingURL: root.appendingPathComponent("active/.niko-staging/\(id.uuidString)"),
                destinationURL: root.appendingPathComponent("active/project"),
                manifest: manifest,
                createdAt: Date(timeIntervalSince1970: 100)
            )
        }
        let firstCandidate = makeCandidate(UUID())
        let secondCandidate = makeCandidate(UUID())

        async let first = Task.detached { try firstStore.claimRestore(firstCandidate) }.value
        async let second = Task.detached { try secondStore.claimRestore(secondCandidate) }.value
        let results = try await [first, second]

        XCTAssertEqual(results.filter(\.isClaimed).count, 1)
        XCTAssertEqual(results.filter(\.isExisting).count, 1)
        XCTAssertEqual(try firstStore.recoverableRestoreRecords().count, 1)
    }

    func testLegacyRestoreSQLiteBlobDefaultsMissingMaterializationRequirementToTrue() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("vault.sqlite"))
        let store = try SQLiteVaultTransferStore(database: database)
        let record = VaultRestoreRecord(
            projectID: ProjectID(),
            archiveGenerationURL: root.appendingPathComponent("archive/generations/project"),
            stagingURL: root.appendingPathComponent("active/.niko-staging/project"),
            destinationURL: root.appendingPathComponent("active/project"),
            manifest: VaultManifest(entries: []),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        var legacyJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
        )
        legacyJSON.removeValue(forKey: "requiresArchiveMaterialization")
        legacyJSON.removeValue(forKey: "supersededBy")
        let legacyBlob = try JSONSerialization.data(withJSONObject: legacyJSON)

        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "INSERT INTO vault_restores(id,project_id,phase,updated_at,record) VALUES(?,?,?,?,?);"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw LegacyBlobFixtureError.prepare
            }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, record.id.uuidString, -1, transient)
            sqlite3_bind_text(statement, 2, record.projectID.description, -1, transient)
            sqlite3_bind_text(statement, 3, record.phase.rawValue, -1, transient)
            sqlite3_bind_double(statement, 4, record.updatedAt.timeIntervalSince1970)
            _ = legacyBlob.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 5, bytes.baseAddress, Int32(bytes.count), transient)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LegacyBlobFixtureError.insert
            }
        }

        let decoded = try XCTUnwrap(store.restoreRecord(id: record.id))

        XCTAssertTrue(decoded.requiresArchiveMaterialization)
        XCTAssertNil(decoded.supersededBy)
    }

    func testSupersededRestoreDoesNotOwnFutureClaimOrRecovery() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteVaultTransferStore(
            databaseURL: root.appendingPathComponent("vault.sqlite")
        )
        let projectID = ProjectID()
        let manifest = VaultManifest(entries: [])
        let archiveURL = root.appendingPathComponent("archive/generations/project")
        let destinationURL = root.appendingPathComponent("active/project")
        var retired = VaultRestoreRecord(
            projectID: projectID,
            archiveGenerationURL: archiveURL,
            stagingURL: root.appendingPathComponent("active/.niko-staging/retired"),
            destinationURL: destinationURL,
            manifest: manifest,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        retired.phase = .superseded
        retired.supersededBy = UUID()
        try store.saveRestore(retired)

        let candidate = VaultRestoreRecord(
            projectID: projectID,
            archiveGenerationURL: archiveURL,
            stagingURL: root.appendingPathComponent("active/.niko-staging/candidate"),
            destinationURL: destinationURL,
            manifest: manifest,
            createdAt: Date(timeIntervalSince1970: 101)
        )

        let result = try store.claimRestore(candidate)

        XCTAssertTrue(result.isClaimed)
        XCTAssertEqual(try store.restoreRecord(id: retired.id), retired)
        XCTAssertEqual(try store.recoverableRestoreRecords().map(\.id), [candidate.id])
    }

    func testRoundTripsTransferAndSelectsOnlyAutomaticallyRecoverableStates() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteVaultTransferStore(databaseURL: root.appendingPathComponent("vault.sqlite"))

        var copying = makeRecord(root: root, state: .copyingToArchiveStaging)
        copying.completedBytes = 41
        copying.error = VaultTransferError(origin: .copyingToArchiveStaging, reason: .sourceMutated, message: "changed")
        var failed = makeRecord(root: root, state: .failedRecoverable)
        failed.retryCount = 2
        let verified = makeRecord(root: root, state: .archiveVerified)
        let manual = makeRecord(root: root, state: .recoveryRequired)
        var superseded = makeRecord(root: root, state: .superseded)
        superseded.supersededBy = verified.id

        try store.save(copying)
        try store.save(failed)
        try store.save(verified)
        try store.save(manual)
        try store.save(superseded)

        XCTAssertEqual(try store.record(id: copying.id), copying)
        XCTAssertEqual(Set(try store.recoverableRecords().map(\.id)), Set([copying.id, failed.id]))
        XCTAssertEqual(try store.record(id: superseded.id), superseded)
    }

    func testAllTransferRecordsSkipsUndecodableRowAndReportsIt() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("vault.sqlite")
        let store = try SQLiteVaultTransferStore(databaseURL: databaseURL)
        let readable = makeRecord(root: root, state: .removingActiveCopy)
        try store.save(readable)
        let unreadableID = UUID()
        try UndecodableVaultJournalRow.insertTransfer(
            id: unreadableID,
            state: VaultTransferState.removingActiveCopy.rawValue,
            databaseURL: databaseURL
        )

        let all = try store.allTransferRecordsReport()
        let recoverable = try store.recoverableRecordsReport()

        XCTAssertEqual(all.records, [readable])
        XCTAssertEqual(all.unreadableRows.count, 1)
        let unreadable = try XCTUnwrap(all.unreadableRows.first)
        XCTAssertEqual(unreadable.journal, .transfers)
        XCTAssertEqual(unreadable.id, unreadableID.uuidString)
        XCTAssertEqual(unreadable.state, VaultTransferState.removingActiveCopy.rawValue)
        XCTAssertEqual(recoverable.records, [readable])
        XCTAssertEqual(recoverable.unreadableRows.map(\.id), [unreadableID.uuidString])
        // Every other reader keeps failing closed on the same row.
        XCTAssertThrowsError(try store.allTransferRecords())
        XCTAssertThrowsError(try store.recoverableRecords())
        XCTAssertThrowsError(try store.claimTransfer(makeRecord(root: root, state: .activeLocal)))
    }

    func testRestoreReconciliationSkipsUndecodableRowAndReportsIt() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("vault.sqlite")
        let store = try SQLiteVaultTransferStore(databaseURL: databaseURL)
        var readable = VaultRestoreRecord(
            projectID: ProjectID(),
            archiveGenerationURL: root.appendingPathComponent("archive/generations/project"),
            stagingURL: root.appendingPathComponent("active/.niko-staging/project"),
            destinationURL: root.appendingPathComponent("active/project"),
            manifest: VaultManifest(entries: []),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        readable.phase = .copyingToActiveStaging
        try store.saveRestore(readable)
        let unreadableID = UUID()
        let unreadableProjectID = ProjectID()
        try UndecodableVaultJournalRow.insertRestore(
            id: unreadableID,
            projectID: unreadableProjectID,
            phase: VaultRestorePhase.copyingToActiveStaging.rawValue,
            databaseURL: databaseURL
        )

        let report = try store.reconcileRestoreRecordsForRecoveryReport()

        XCTAssertEqual(report.records, [readable])
        XCTAssertEqual(report.unreadableRows, [VaultJournalUnreadableRow(
            journal: .restores,
            id: unreadableID.uuidString,
            state: VaultRestorePhase.copyingToActiveStaging.rawValue,
            projectID: unreadableProjectID.description,
            reason: try XCTUnwrap(report.unreadableRows.first?.reason)
        )])
        XCTAssertThrowsError(try store.reconcileRestoreRecordsForRecovery())
        XCTAssertThrowsError(try store.recoverableRestoreRecords())
    }

    func testRestoreReconciliationHoldsEveryConflictComponentTouchingAnUnreadableProject() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("vault.sqlite")
        let store = try SQLiteVaultTransferStore(databaseURL: databaseURL)
        func makeRestore(projectID: ProjectID, destination: String, updatedAt: TimeInterval) -> VaultRestoreRecord {
            var record = VaultRestoreRecord(
                projectID: projectID,
                archiveGenerationURL: root.appendingPathComponent("archive/generations/\(UUID().uuidString)"),
                stagingURL: root.appendingPathComponent("active/.niko-staging/\(UUID().uuidString)"),
                destinationURL: root.appendingPathComponent("active/\(destination)"),
                manifest: VaultManifest(entries: []),
                createdAt: Date(timeIntervalSince1970: 100)
            )
            record.phase = .copyingToActiveStaging
            record.updatedAt = Date(timeIntervalSince1970: updatedAt)
            return record
        }
        let fencedProject = ProjectID()
        let held = makeRestore(projectID: fencedProject, destination: "Shared", updatedAt: 200)
        // Another project restoring into the same destination: one component.
        let sharing = makeRestore(projectID: ProjectID(), destination: "Shared", updatedAt: 210)
        let independent = makeRestore(projectID: ProjectID(), destination: "Elsewhere", updatedAt: 220)
        try store.saveRestore(held)
        try store.saveRestore(sharing)
        try store.saveRestore(independent)
        try UndecodableVaultJournalRow.insertRestore(
            id: UUID(),
            projectID: fencedProject,
            phase: VaultRestorePhase.copyingToActiveStaging.rawValue,
            databaseURL: databaseURL
        )

        let report = try store.reconcileRestoreRecordsForRecoveryReport()

        XCTAssertEqual(report.records.map(\.id), [independent.id])
        // Nothing in the held component was retired.
        XCTAssertEqual(try store.restoreRecord(id: held.id), held)
        XCTAssertEqual(try store.restoreRecord(id: sharing.id), sharing)

        // A row whose project column is empty could belong to any project.
        try UndecodableVaultJournalRow.insertRestore(
            id: UUID(),
            projectIDColumn: "",
            phase: VaultRestorePhase.materializingArchive.rawValue,
            databaseURL: databaseURL
        )
        XCTAssertTrue(try store.reconcileRestoreRecordsForRecoveryReport().records.isEmpty)
        XCTAssertEqual(try store.restoreRecord(id: independent.id), independent)
    }

    func testSaveUpdatesExistingRecordInsteadOfDuplicatingIt() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteVaultTransferStore(databaseURL: root.appendingPathComponent("vault.sqlite"))
        var record = makeRecord(root: root, state: .archiveEligible)
        try store.save(record)
        record.state = .preparingArchive
        record.retryCount = 1
        try store.save(record)

        XCTAssertEqual(try store.record(id: record.id), record)
        XCTAssertEqual(try store.recoverableRecords().filter { $0.id == record.id }.count, 1)
    }

    func testTransferQueriesFailClosedOnMidIterationStepError() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var store = try SQLiteVaultTransferStore(databaseURL: root.appendingPathComponent("vault.sqlite"))
        let projectID = ProjectID()
        func makeTransfer(state: VaultTransferState) -> VaultTransferRecord {
            VaultTransferRecord(
                projectID: projectID,
                sourceURL: root.appendingPathComponent("active/project"),
                stagingURL: root.appendingPathComponent("archive/.niko-staging/\(UUID().uuidString)"),
                destinationURL: root.appendingPathComponent("archive/generations/\(UUID().uuidString)"),
                state: state,
                createdAt: Date(timeIntervalSince1970: 100)
            )
        }
        let copying = makeTransfer(state: .copyingToArchiveStaging)
        let failed = makeTransfer(state: .failedRecoverable)
        let verified = makeTransfer(state: .archiveVerified)
        try store.save(copying)
        try store.save(failed)
        try store.save(verified)
        // Sanity: without fault injection all three rows read back.
        XCTAssertEqual(try store.allTransferRecords().count, 3)

        // Fail the second sqlite3_step with BUSY after one ROW: the old
        // `while step == ROW` loop returned the partial first row as success.
        // The fixed loop must throw StoreError.step instead.
        func expectStepFailure(_ query: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
            let counter = StepFaultCounter()
            store.stepForTesting = { statement in
                counter.calls += 1
                if counter.calls == 2 { return SQLITE_BUSY }
                return sqlite3_step(statement)
            }
            defer { store.stepForTesting = nil }
            XCTAssertThrowsError(try query(), file: file, line: line) { error in
                guard case SQLiteArchiveDatabase.StoreError.step = error else {
                    XCTFail("expected StoreError.step, got \(error)", file: file, line: line)
                    return
                }
            }
        }
        expectStepFailure { _ = try store.allTransferRecords() }
        expectStepFailure { _ = try store.recoverableRecords() }
        // The recovery reports skip undecodable rows, never failed steps.
        expectStepFailure { _ = try store.allTransferRecordsReport() }
        expectStepFailure { _ = try store.recoverableRecordsReport() }
        expectStepFailure { _ = try store.record(id: copying.id) }
        expectStepFailure { _ = try store.verifiedArchiveGeneration(projectID: projectID) }
        // Clearing the seam restores successful reads.
        store.stepForTesting = nil
        XCTAssertEqual(try store.allTransferRecords().count, 3)
    }

    func testRestoreQueriesFailClosedOnMidIterationStepError() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var store = try SQLiteVaultTransferStore(databaseURL: root.appendingPathComponent("vault.sqlite"))
        let manifest = VaultManifest(entries: [])
        func makeRestore() -> VaultRestoreRecord {
            VaultRestoreRecord(
                projectID: ProjectID(),
                archiveGenerationURL: root.appendingPathComponent("archive/generations/\(UUID().uuidString)"),
                stagingURL: root.appendingPathComponent("active/.niko-staging/\(UUID().uuidString)"),
                destinationURL: root.appendingPathComponent("active/\(UUID().uuidString)"),
                manifest: manifest,
                createdAt: Date(timeIntervalSince1970: 100)
            )
        }
        let first = makeRestore()
        let second = makeRestore()
        try store.saveRestore(first)
        try store.saveRestore(second)
        XCTAssertEqual(try store.recoverableRestoreRecords().count, 2)

        func expectStepFailure(_ query: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
            let counter = StepFaultCounter()
            store.stepForTesting = { statement in
                counter.calls += 1
                if counter.calls == 2 { return SQLITE_IOERR }
                return sqlite3_step(statement)
            }
            defer { store.stepForTesting = nil }
            XCTAssertThrowsError(try query(), file: file, line: line) { error in
                guard case SQLiteArchiveDatabase.StoreError.step = error else {
                    XCTFail("expected StoreError.step, got \(error)", file: file, line: line)
                    return
                }
            }
        }
        expectStepFailure { _ = try store.recoverableRestoreRecords() }
        expectStepFailure { _ = try store.restoreRecord(id: first.id) }
        store.stepForTesting = nil
        XCTAssertEqual(try store.recoverableRestoreRecords().count, 2)
    }

    func testVerifiedArchiveGenerationUsesImmutableCreationOrder() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteVaultTransferStore(databaseURL: root.appendingPathComponent("vault.sqlite"))
        let projectID = ProjectID()
        let olderID = try XCTUnwrap(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        let newerID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))

        func makeVerifiedGeneration(id: UUID, createdAt: Date) throws -> VaultTransferRecord {
            let destination = root.appendingPathComponent("archive/generations/\(id.uuidString.lowercased())")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try Data(id.uuidString.utf8).write(to: destination.appendingPathComponent("Song.cpr"))
            let manifest = try VaultManifestBuilder().build(at: destination)
            var record = VaultTransferRecord(
                id: id,
                projectID: projectID,
                sourceURL: root.appendingPathComponent("active/project"),
                stagingURL: root.appendingPathComponent("archive/.niko-staging/\(id.uuidString.lowercased())"),
                destinationURL: destination,
                state: .archivedLocal,
                createdAt: createdAt
            )
            record.manifestID = manifest.id
            record.manifest = manifest
            record.durability = .verifiedLocal
            return record
        }

        var older = try makeVerifiedGeneration(
            id: olderID,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        var newer = try makeVerifiedGeneration(
            id: newerID,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        older.updatedAt = Date(timeIntervalSince1970: 300)
        newer.updatedAt = Date(timeIntervalSince1970: 200)
        try store.save(older)
        try store.save(newer)

        XCTAssertEqual(try store.verifiedArchiveGeneration(projectID: projectID)?.id, newerID)
    }

    func testVerifiedArchiveGenerationFailsClosedForZeroLengthEligibleBlob() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("vault.sqlite"))
        let store = try SQLiteVaultTransferStore(database: database)
        let projectID = ProjectID()
        let older = VaultTransferRecord(
            projectID: projectID,
            sourceURL: root.appendingPathComponent("active/project"),
            stagingURL: root.appendingPathComponent("archive/.niko-staging/older"),
            destinationURL: root.appendingPathComponent("archive/generations/older"),
            state: .archivedLocal,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try store.save(older)

        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "INSERT INTO vault_transfers(id,state,updated_at,record) VALUES(?,?,?,zeroblob(0));"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw LegacyBlobFixtureError.prepare
            }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, UUID().uuidString, -1, transient)
            sqlite3_bind_text(statement, 2, VaultTransferState.archiveVerified.rawValue, -1, transient)
            sqlite3_bind_double(statement, 3, Date(timeIntervalSince1970: 200).timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LegacyBlobFixtureError.insert
            }
        }

        XCTAssertThrowsError(try store.verifiedArchiveGeneration(projectID: projectID)) { error in
            guard case SQLiteArchiveDatabase.StoreError.decode = error else {
                return XCTFail("expected SQLite decode error, got \(error)")
            }
        }
    }

    func testDecodesLegacySQLiteBlobWithoutNextRetryAt() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("vault.sqlite"))
        let store = try SQLiteVaultTransferStore(database: database)
        var legacyRecord = makeRecord(root: root, state: .failedRecoverable)
        legacyRecord.retryCount = 2
        legacyRecord.error = VaultTransferError(
            origin: .awaitingProviderDurability,
            reason: .providerUnsynced,
            message: "legacy durability failure"
        )
        let legacyManifest = VaultManifest(entries: [
            .init(
                relativePath: "Synthetic Song.cpr",
                type: .regularFile,
                byteCount: 13,
                modifiedAt: Date(timeIntervalSince1970: 1),
                sha256: "legacy"
            ),
        ])
        legacyRecord.manifestID = legacyManifest.id
        legacyRecord.manifest = legacyManifest
        var legacyJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyRecord)) as? [String: Any]
        )
        legacyJSON.removeValue(forKey: "nextRetryAt")
        let legacyBlob = try JSONSerialization.data(withJSONObject: legacyJSON)

        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            let sql = "INSERT INTO vault_transfers(id,state,updated_at,record) VALUES(?,?,?,?);"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw LegacyBlobFixtureError.prepare
            }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, legacyRecord.id.uuidString, -1, transient)
            sqlite3_bind_text(statement, 2, legacyRecord.state.rawValue, -1, transient)
            sqlite3_bind_double(statement, 3, legacyRecord.updatedAt.timeIntervalSince1970)
            _ = legacyBlob.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), transient)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LegacyBlobFixtureError.insert
            }
        }

        let decoded = try XCTUnwrap(store.record(id: legacyRecord.id))

        XCTAssertEqual(decoded, legacyRecord)
        XCTAssertNil(decoded.nextRetryAt)
        XCTAssertNil(decoded.supersededBy)
        XCTAssertNil(decoded.manifest?.rootAllocatedByteCount)
        XCTAssertNil(decoded.manifest?.rootExtendedAttributeBytes)
        XCTAssertNil(decoded.manifest?.entries.first?.allocatedByteCount)
        XCTAssertNil(decoded.manifest?.entries.first?.extendedAttributeBytes)
    }

    private func makeRecord(root: URL, state: VaultTransferState) -> VaultTransferRecord {
        VaultTransferRecord(
            projectID: ProjectID(),
            sourceURL: root.appendingPathComponent("active/project"),
            stagingURL: root.appendingPathComponent("archive/.niko-staging/project"),
            destinationURL: root.appendingPathComponent("archive/generations/project"),
            state: state,
            createdAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sqlite-vault-transfer-\(UUID().uuidString)", isDirectory: true)
    }
}

private extension VaultTransferClaimResult {
    var isClaimed: Bool {
        if case .claimed = self { return true }
        return false
    }

    var isExisting: Bool {
        if case .existing = self { return true }
        return false
    }
}

private extension VaultRestoreClaimResult {
    var isClaimed: Bool {
        if case .claimed = self { return true }
        return false
    }

    var isExisting: Bool {
        if case .existing = self { return true }
        return false
    }
}

private enum LegacyBlobFixtureError: Error {
    case prepare
    case insert
}

private final class StepFaultCounter: @unchecked Sendable {
    var calls = 0
}
