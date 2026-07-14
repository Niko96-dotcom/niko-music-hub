import XCTest
@testable import NikoMusicCore

final class SQLiteVaultTransferStoreTests: XCTestCase {
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

        try store.save(copying)
        try store.save(failed)
        try store.save(verified)
        try store.save(manual)

        XCTAssertEqual(try store.record(id: copying.id), copying)
        XCTAssertEqual(Set(try store.recoverableRecords().map(\.id)), Set([copying.id, failed.id]))
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
