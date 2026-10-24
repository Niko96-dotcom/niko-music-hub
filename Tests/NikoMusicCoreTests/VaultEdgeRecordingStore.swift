import Foundation
@testable import NikoMusicCore

struct VaultTransferEdge: Hashable, Sendable, CustomStringConvertible {
    let from: VaultTransferState
    let to: VaultTransferState

    init(_ from: VaultTransferState, _ to: VaultTransferState) {
        self.from = from
        self.to = to
    }

    var description: String { "\(from.rawValue) → \(to.rawValue)" }
}

struct VaultRestoreEdge: Hashable, Sendable, CustomStringConvertible {
    let from: VaultRestorePhase
    let to: VaultRestorePhase

    init(_ from: VaultRestorePhase, _ to: VaultRestorePhase) {
        self.from = from
        self.to = to
    }

    var description: String { "\(from.rawValue) → \(to.rawValue)" }
}

/// Every saved state change the Vault suites made, observed on 2026-10-24 at
/// 4302564: each engine save logged the persisted state before and after while
/// every test whose name matches Vault, Restore, Recovery, Archive, Workflow,
/// Done, KeepLocal or Friends ran (temporary logging, not committed). A
/// recorded edge outside these lists is a path nobody has observed yet.
enum VaultObservedEdges {
    static let transfer: Set<VaultTransferEdge> = [
        // Archive chain.
        .init(.activeLocal, .archiveEligible),
        .init(.archiveEligible, .preparingArchive),
        .init(.preparingArchive, .copyingToArchiveStaging),
        .init(.copyingToArchiveStaging, .verifyingArchiveStaging),
        .init(.verifyingArchiveStaging, .awaitingProviderDurability),
        .init(.awaitingProviderDurability, .promotingArchiveGeneration),
        .init(.promotingArchiveGeneration, .archiveVerified),
        // A stopped or failed archive phase.
        .init(.preparingArchive, .failedRecoverable),
        .init(.copyingToArchiveStaging, .failedRecoverable),
        .init(.verifyingArchiveStaging, .failedRecoverable),
        .init(.awaitingProviderDurability, .failedRecoverable),
        .init(.promotingArchiveGeneration, .failedRecoverable),
        // An occupied generation folder.
        .init(.promotingArchiveGeneration, .recoveryRequired),
        // Removal, and the re-proof of a restored project's generation.
        .init(.archiveVerified, .removingActiveCopy),
        .init(.archivedLocal, .archiveVerified),
        .init(.removingActiveCopy, .evictingProviderCache),
        .init(.evictingProviderCache, .archivedLocal),
        // Refused or stopped before `removeItem`.
        .init(.removingActiveCopy, .archiveVerified),
        // Stopped after `removeItem`, or found interrupted at launch.
        .init(.removingActiveCopy, .recoveryRequired),
        .init(.evictingProviderCache, .recoveryRequired),
        // Launch: legacy destructive failure, survivor retirement, retry.
        .init(.failedRecoverable, .recoveryRequired),
        .init(.failedRecoverable, .superseded),
        .init(.failedRecoverable, .preparingArchive),
        .init(.failedRecoverable, .copyingToArchiveStaging),
        .init(.failedRecoverable, .verifyingArchiveStaging),
        .init(.failedRecoverable, .awaitingProviderDurability),
        // Explicit recovery of an interrupted removal.
        .init(.recoveryRequired, .archiveVerified),
    ]

    static let restore: Set<VaultRestoreEdge> = [
        .init(.materializingArchive, .copyingToActiveStaging),
        .init(.copyingToActiveStaging, .verifyingActiveStaging),
        .init(.verifyingActiveStaging, .promotingActiveCopy),
        .init(.promotingActiveCopy, .persistingActiveLocation),
        .init(.persistingActiveLocation, .openingInCubase),
        // The staging copy is gone and the Vault copy is not local.
        .init(.copyingToActiveStaging, .materializingArchive),
        // Launch reconcile retires a losing duplicate.
        .init(.copyingToActiveStaging, .superseded),
    ]
}

/// The real SQLite journal, plus a log of every saved change of a transfer
/// state or a restore phase as a (from, to) edge. A creation is not an edge.
final class VaultEdgeRecordingStore: VaultTransferStoring, VaultRestoreStoring, VaultArchiveGenerationResolving,
    VaultProjectionSupplementStoring, @unchecked Sendable {
    let base: SQLiteVaultTransferStore
    private let lock = NSLock()
    private var storedTransferEdges: [VaultTransferEdge] = []
    private var storedRestoreEdges: [VaultRestoreEdge] = []
    private var failingSaveState: VaultTransferState?
    private var failsRecoveryPersistenceProofs = false

    init(databaseURL: URL) throws {
        base = try SQLiteVaultTransferStore(databaseURL: databaseURL)
    }

    var transferEdges: [VaultTransferEdge] { lock.withLock { storedTransferEdges } }
    var restoreEdges: [VaultRestoreEdge] { lock.withLock { storedRestoreEdges } }

    /// The next save of a transfer in `state` throws, as a full disk would.
    func failNextSave(of state: VaultTransferState) {
        lock.withLock { failingSaveState = state }
    }

    /// Every later journal proof throws, as a catalog that cannot checkpoint would.
    func failRecoveryPersistenceProofs() {
        lock.withLock { failsRecoveryPersistenceProofs = true }
    }

    func save(_ record: VaultTransferRecord) throws {
        let fails = lock.withLock {
            guard failingSaveState == record.state else { return false }
            failingSaveState = nil
            return true
        }
        if fails { throw SQLiteArchiveDatabase.StoreError.step("injected save failure") }
        let previous = try base.record(id: record.id)
        try base.save(record)
        if let previous, previous.state != record.state {
            lock.withLock { storedTransferEdges.append(.init(previous.state, record.state)) }
        }
    }

    func claimTransfer(_ record: VaultTransferRecord) throws -> VaultTransferClaimResult {
        try base.claimTransfer(record)
    }

    func record(id: UUID) throws -> VaultTransferRecord? { try base.record(id: id) }
    func recoverableRecords() throws -> [VaultTransferRecord] { try base.recoverableRecords() }
    func allTransferRecords() throws -> [VaultTransferRecord] { try base.allTransferRecords() }

    func recoverableRecordsReport() throws -> VaultJournalReadReport<VaultTransferRecord> {
        try base.recoverableRecordsReport()
    }

    func allTransferRecordsReport() throws -> VaultJournalReadReport<VaultTransferRecord> {
        try base.allTransferRecordsReport()
    }

    func proveRecoveryPersistence() throws {
        if lock.withLock({ failsRecoveryPersistenceProofs }) {
            throw VaultTransferPersistenceProofError.unproven("injected proof failure")
        }
        try base.proveRecoveryPersistence()
    }

    func verifiedArchiveGeneration(projectID: ProjectID) throws -> VaultTransferRecord? {
        try base.verifiedArchiveGeneration(projectID: projectID)
    }

    func compareAndSetProjectionSupplement(
        _ supplement: VaultProjectionSupplement,
        transferID: UUID,
        expectedManifest: VaultManifest,
        expectedDestinationURL: URL,
        expectedState: VaultTransferState
    ) throws -> VaultTransferRecord {
        try base.compareAndSetProjectionSupplement(
            supplement,
            transferID: transferID,
            expectedManifest: expectedManifest,
            expectedDestinationURL: expectedDestinationURL,
            expectedState: expectedState
        )
    }

    func saveRestore(_ record: VaultRestoreRecord) throws {
        let previous = try base.restoreRecord(id: record.id)
        try base.saveRestore(record)
        if let previous, previous.phase != record.phase {
            lock.withLock { storedRestoreEdges.append(.init(previous.phase, record.phase)) }
        }
    }

    func claimRestore(_ record: VaultRestoreRecord) throws -> VaultRestoreClaimResult {
        try base.claimRestore(record)
    }

    func restoreRecord(id: UUID) throws -> VaultRestoreRecord? { try base.restoreRecord(id: id) }
    func recoverableRestoreRecords() throws -> [VaultRestoreRecord] { try base.recoverableRestoreRecords() }

    func reconcileRestoreRecordsForRecovery() throws -> [VaultRestoreRecord] {
        try recordingReconcile { try base.reconcileRestoreRecordsForRecovery() }
    }

    func reconcileRestoreRecordsForRecoveryReport() throws -> VaultJournalReadReport<VaultRestoreRecord> {
        try recordingReconcile { try base.reconcileRestoreRecordsForRecoveryReport() }
    }

    /// The reconcile retires losers inside the base store's own transaction,
    /// so compare each incomplete restore's phase before and after it.
    private func recordingReconcile<T>(_ reconcile: () throws -> T) throws -> T {
        let before = try base.recoverableRestoreRecords()
        let result = try reconcile()
        for record in before {
            if let after = try base.restoreRecord(id: record.id), after.phase != record.phase {
                lock.withLock { storedRestoreEdges.append(.init(record.phase, after.phase)) }
            }
        }
        return result
    }
}

/// Logs the file operations that change a tree, so a test can show what a
/// relaunch replays.
final class VaultMutationRecordingFileManager: FileManager {
    private let log: VaultMutationLog

    init(log: VaultMutationLog) {
        self.log = log
        super.init()
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        log.append("copy", dstURL)
        try super.copyItem(at: srcURL, to: dstURL)
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        log.append("move", dstURL)
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func removeItem(at URL: URL) throws {
        log.append("remove", URL)
        try super.removeItem(at: URL)
    }
}

final class VaultMutationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedOperations: [String] = []

    /// Each entry is the operation and the last path component it wrote.
    var operations: [String] { lock.withLock { storedOperations } }
    func reset() { lock.withLock { storedOperations.removeAll() } }

    func append(_ operation: String, _ url: URL) {
        lock.withLock { storedOperations.append("\(operation) \(url.lastPathComponent)") }
    }
}
