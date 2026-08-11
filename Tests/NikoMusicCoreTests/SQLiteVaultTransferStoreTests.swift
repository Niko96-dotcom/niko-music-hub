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
