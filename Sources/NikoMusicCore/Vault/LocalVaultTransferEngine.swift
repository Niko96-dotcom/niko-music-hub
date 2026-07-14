import Foundation

public enum VaultTransferFaultPoint: String, CaseIterable, Sendable {
    case preparingArchive
    case copyingToArchiveStaging
    case verifyingArchiveStaging
    case awaitingProviderDurability
    case promotingArchiveGeneration
}

/// Throw this from a fault injector to model process termination. The engine
/// deliberately leaves the already-persisted phase untouched for launch recovery.
public struct VaultTransferInterruption: Error, Equatable, Sendable {
    public init() {}
}

public enum LocalVaultTransferError: Error, Equatable, Sendable {
    case sourceOutsideActiveRoot
    case overlappingRoots
    case unsafeStagingPath
    case unsafeDestinationPath
    case occupiedDestination
    case sourceMutated
    case missingManifest
    case missingPersistedArchiveEvidence
}

public actor LocalVaultTransferEngine {
    public typealias FaultInjector = @Sendable (VaultTransferFaultPoint, VaultTransferRecord) throws -> Void

    private let activeRoot: URL
    private let archiveRoot: URL
    private let store: any VaultTransferStoring
    private let provider: any ArchiveStorageProvider
    private let fileManager: FileManager
    private let manifestBuilder: VaultManifestBuilder
    private let faultInjector: FaultInjector?
    private let now: @Sendable () -> Date

    public init(
        activeRoot: URL,
        archiveRoot: URL,
        store: any VaultTransferStoring,
        provider: (any ArchiveStorageProvider)? = nil,
        fileManager: FileManager = .default,
        faultInjector: FaultInjector? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        let active = activeRoot.standardizedFileURL.resolvingSymlinksInPath()
        let archive = archiveRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard !Self.contains(active, archive), !Self.contains(archive, active) else {
            throw LocalVaultTransferError.overlappingRoots
        }
        self.activeRoot = active
        self.archiveRoot = archive
        self.store = store
        self.provider = provider ?? LocalFolderArchiveStorage(root: archive, fileManager: fileManager)
        self.fileManager = fileManager
        self.manifestBuilder = VaultManifestBuilder(fileManager: fileManager)
        self.faultInjector = faultInjector
        self.now = now
    }

    @discardableResult
    public func archive(projectID: ProjectID, sourceURL: URL) async throws -> VaultTransferRecord {
        let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.contains(activeRoot, source), source != activeRoot else {
            throw LocalVaultTransferError.sourceOutsideActiveRoot
        }
        let transferID = UUID()
        let staging = archiveRoot
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent(transferID.uuidString.lowercased(), isDirectory: true)
        let generation = archiveRoot
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent("generation-\(transferID.uuidString.lowercased())", isDirectory: true)
        var record = VaultTransferRecord(
            id: transferID,
            projectID: projectID,
            sourceURL: source,
            stagingURL: staging,
            destinationURL: generation,
            createdAt: now()
        )
        try persist(&record)
        try advance(&record, to: .archiveEligible)
        return try await execute(record)
    }

    /// Relaunch entry point. Incomplete records are resumed idempotently before
    /// callers schedule any new work.
    @discardableResult
    public func recoverAtLaunch() async -> [VaultTransferRecord] {
        guard let records = try? store.recoverableRecords() else { return [] }
        var results: [VaultTransferRecord] = []
        for var record in records {
            if record.state == .failedRecoverable, let origin = record.error?.origin {
                record.state = origin
                record.error = nil
                record.retryCount += 1
                try? persist(&record)
            }
            do { results.append(try await execute(record)) }
            catch is VaultTransferInterruption { results.append((try? store.record(id: record.id)) ?? record) }
            catch { results.append((try? store.record(id: record.id)) ?? record) }
        }
        return results
    }

    /// Removes the Active copy only after independently reloading the terminal
    /// archive record and re-verifying its manifest. Automatic callers should
    /// perform their final activity/open-file probe immediately before calling.
    @discardableResult
    public func removeActiveCopy(after archivedRecord: VaultTransferRecord) async throws -> VaultTransferRecord {
        guard
            archivedRecord.state == .archiveVerified,
            let persisted = try store.record(id: archivedRecord.id),
            persisted.state == .archiveVerified,
            persisted.projectID == archivedRecord.projectID,
            persisted.destinationURL == archivedRecord.destinationURL,
            persisted.manifestID == archivedRecord.manifestID,
            let manifest = persisted.manifest,
            let durability = persisted.durability
        else {
            throw LocalVaultTransferError.missingPersistedArchiveEvidence
        }
        try manifestBuilder.verify(manifest, at: persisted.destinationURL)
        var record = persisted
        record.state = try ProjectVaultStateMachine().applying(
            .beginRemovingActiveCopy(VaultRemovalEvidence(
                manifestVerified: true,
                archiveDurability: durability,
                metadataPersisted: true
            )),
            to: record.state
        )
        try persist(&record)
        return try await execute(record)
    }

    private func execute(_ initial: VaultTransferRecord) async throws -> VaultTransferRecord {
        var record = initial
        do {
            while true {
                switch record.state {
                case .activeLocal:
                    try advance(&record, to: .archiveEligible)
                case .archiveEligible:
                    try advance(&record, to: .preparingArchive)
                case .preparingArchive:
                    try inject(.preparingArchive, record)
                    try validatePaths(record)
                    try await provider.prepareForWrite(at: archiveRoot)
                    try advance(&record, to: .copyingToArchiveStaging)
                case .copyingToArchiveStaging:
                    try inject(.copyingToArchiveStaging, record)
                    try copyToStaging(&record)
                    try advance(&record, to: .verifyingArchiveStaging)
                case .verifyingArchiveStaging:
                    try inject(.verifyingArchiveStaging, record)
                    guard let manifest = record.manifest else { throw LocalVaultTransferError.missingManifest }
                    try manifestBuilder.verify(manifest, at: record.stagingURL)
                    try advance(&record, to: .awaitingProviderDurability)
                case .awaitingProviderDurability:
                    try inject(.awaitingProviderDurability, record)
                    record.durability = try await provider.waitUntilDurable(record.stagingURL)
                    try persist(&record)
                    try advance(&record, to: .promotingArchiveGeneration)
                case .promotingArchiveGeneration:
                    try inject(.promotingArchiveGeneration, record)
                    try promote(&record)
                    // The provider barrier before promotion covers the staged
                    // bytes. The final rename is another provider-visible
                    // mutation, so it must also become durable before this
                    // generation can authorize removal of the Active copy.
                    record.durability = try await provider.waitUntilDurable(record.destinationURL)
                    try persist(&record)
                    record.state = .archiveVerified
                    record.error = nil
                    try persist(&record)
                    return record
                case .archiveVerified:
                    return record
                case .removingActiveCopy:
                    try validateRemovalEvidence(record)
                    if fileManager.fileExists(atPath: record.sourceURL.path) {
                        try fileManager.removeItem(at: record.sourceURL)
                    }
                    try advance(&record, to: .evictingProviderCache)
                case .evictingProviderCache:
                    let result = try await provider.evictIfSupported(record.destinationURL)
                    try advance(&record, to: result == .evicted ? .archivedOnlineOnly : .archivedLocal)
                    return record
                case .archivedLocal, .archivedOnlineOnly:
                    return record
                case .failedRecoverable, .recoveryRequired:
                    return record
                default:
                    throw LocalVaultTransferError.unsafeDestinationPath
                }
            }
        } catch is VaultTransferInterruption {
            throw VaultTransferInterruption()
        } catch {
            let origin = record.state
            let reason = failureReason(for: error)
            record.error = VaultTransferError(origin: origin, reason: reason, message: String(describing: error))
            record.state = reason == .occupiedDestination ? .recoveryRequired : .failedRecoverable
            record.retryCount += 1
            try persist(&record)
            throw error
        }
    }

    private func copyToStaging(_ record: inout VaultTransferRecord) throws {
        try validatePaths(record)
        let sourceBefore = try manifestBuilder.build(at: record.sourceURL)
        if fileManager.fileExists(atPath: record.stagingURL.path) {
            guard Self.contains(archiveRoot.appendingPathComponent(".niko-staging", isDirectory: true), record.stagingURL) else {
                throw LocalVaultTransferError.unsafeStagingPath
            }
            try fileManager.removeItem(at: record.stagingURL)
        }
        try fileManager.createDirectory(at: record.stagingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: record.sourceURL, to: record.stagingURL)
        let sourceAfter = try manifestBuilder.build(at: record.sourceURL, id: sourceBefore.id, createdAt: sourceBefore.createdAt)
        guard sourceBefore.entries == sourceAfter.entries else { throw LocalVaultTransferError.sourceMutated }
        try manifestBuilder.verify(sourceBefore, at: record.stagingURL)
        record.manifestID = sourceBefore.id
        record.manifest = sourceBefore
        record.totalBytes = sourceBefore.totalBytes
        record.completedBytes = sourceBefore.totalBytes
        try persist(&record)
    }

    private func promote(_ record: inout VaultTransferRecord) throws {
        try validatePaths(record)
        guard let manifest = record.manifest else { throw LocalVaultTransferError.missingManifest }
        let destinationExists = fileManager.fileExists(atPath: record.destinationURL.path)
        let stagingExists = fileManager.fileExists(atPath: record.stagingURL.path)
        if destinationExists {
            guard !stagingExists else { throw LocalVaultTransferError.occupiedDestination }
            // A previous rename completed before process termination. Verify it
            // rather than overwrite or create a second generation.
            try manifestBuilder.verify(manifest, at: record.destinationURL)
            return
        }
        guard stagingExists else { throw VaultManifestError.missingRoot }
        try fileManager.createDirectory(at: record.destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: record.stagingURL, to: record.destinationURL)
        try manifestBuilder.verify(manifest, at: record.destinationURL)
    }

    private func validatePaths(_ record: VaultTransferRecord) throws {
        let stagingRoot = archiveRoot.appendingPathComponent(".niko-staging", isDirectory: true)
        let generationsRoot = archiveRoot.appendingPathComponent("generations", isDirectory: true)
        guard Self.contains(activeRoot, record.sourceURL), record.sourceURL != activeRoot else {
            throw LocalVaultTransferError.sourceOutsideActiveRoot
        }
        guard Self.contains(stagingRoot, record.stagingURL), record.stagingURL != stagingRoot else {
            throw LocalVaultTransferError.unsafeStagingPath
        }
        guard Self.contains(generationsRoot, record.destinationURL), record.destinationURL != generationsRoot else {
            throw LocalVaultTransferError.unsafeDestinationPath
        }
    }

    private func validateRemovalEvidence(_ record: VaultTransferRecord) throws {
        guard
            let persisted = try store.record(id: record.id),
            persisted.state == .removingActiveCopy,
            persisted.durability != nil,
            let manifest = persisted.manifest,
            persisted.manifestID == manifest.id,
            persisted.destinationURL == record.destinationURL,
            persisted.sourceURL == record.sourceURL
        else {
            throw LocalVaultTransferError.missingPersistedArchiveEvidence
        }
        try validatePaths(persisted)
        try manifestBuilder.verify(manifest, at: persisted.destinationURL)
        // Detect any source mutation after the archive copy. A changed or
        // unreadable source is retained for manual review.
        try manifestBuilder.verify(manifest, at: persisted.sourceURL)
    }

    private func advance(_ record: inout VaultTransferRecord, to state: VaultTransferState) throws {
        record.state = try ProjectVaultStateMachine().applying(.advance(to: state), to: record.state)
        try persist(&record)
    }

    private func persist(_ record: inout VaultTransferRecord) throws {
        record.updatedAt = now()
        try store.save(record)
    }

    private func inject(_ point: VaultTransferFaultPoint, _ record: VaultTransferRecord) throws {
        try faultInjector?(point, record)
    }

    private func failureReason(for error: Error) -> VaultFailureReason {
        switch error {
        case LocalVaultTransferError.sourceMutated: .sourceMutated
        case LocalVaultTransferError.occupiedDestination: .occupiedDestination
        case VaultManifestError.mismatch: .integrityMismatch
        case LocalFolderStorageError.unreadable, LocalFolderStorageError.unwritable: .permissionLost
        default: .unknown
        }
    }

    private static func contains(_ root: URL, _ candidate: URL) -> Bool {
        let root = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let candidate = candidate.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return candidate.count >= root.count && Array(candidate.prefix(root.count)) == root
    }
}
