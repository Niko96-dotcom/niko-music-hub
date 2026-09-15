import Foundation
import Darwin

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

public enum LocalVaultTransferError: Error, LocalizedError, Equatable, Sendable {
    case sourceOutsideActiveRoot
    case overlappingRoots
    case unsafeStagingPath
    case unsafeDestinationPath
    case occupiedDestination
    case sourceMutated
    case missingManifest
    case missingPersistedArchiveEvidence
    case writeAdmissionRequired
    case removalAdmissionRequired
    case transferAlreadyOwned
    case crossVolumePromotion
    case writeTargetVolumeMismatch

    public var errorDescription: String? {
        switch self {
        case .sourceMutated:
            "Project files changed while archiving. Finish saving and retry. The Active copy was kept."
        case .sourceOutsideActiveRoot:
            "The project is outside the configured Active Projects folder. Check the selected folders."
        case .overlappingRoots:
            "Active Projects and Archive / Vault must be separate folders."
        case .unsafeStagingPath, .unsafeDestinationPath:
            "The saved transfer paths do not match the configured folders, or contain an unsafe link. Reconnect the original folders before retrying."
        case .occupiedDestination:
            "The destination already contains files. Existing copies were kept."
        case .missingManifest, .missingPersistedArchiveEvidence:
            "The archive has no valid verification record. Existing copies were kept."
        case .writeAdmissionRequired, .removalAdmissionRequired:
            "The required Project Vault safety check is unavailable. Existing copies were kept."
        case .transferAlreadyOwned:
            "This project already has an unfinished transfer. Review or retry that transfer first."
        case .crossVolumePromotion, .writeTargetVolumeMismatch:
            "The destination volume changed during the transfer. Reconnect the original volume and retry."
        }
    }
}

public enum VaultTransferRetryPolicy {
    public static func permitsNondestructiveArchiveOrigin(_ state: VaultTransferState) -> Bool {
        switch state {
        case .activeLocal, .archiveEligible, .preparingArchive,
             .copyingToArchiveStaging, .verifyingArchiveStaging,
             .awaitingProviderDurability, .promotingArchiveGeneration:
            true
        default:
            false
        }
    }
}

public enum VaultTransferOwnershipPolicy {
    public static func isVerifiedTerminal(_ state: VaultTransferState) -> Bool {
        [.archiveVerified, .archivedLocal, .archivedOnlineOnly].contains(state)
    }

    public static func ownsProject(_ state: VaultTransferState) -> Bool {
        !isVerifiedTerminal(state) && state != .superseded
    }
}

public enum VaultWriteTarget: Equatable, Sendable {
    case archive
    case active
}

public enum VaultWriteProjection: Equatable, Sendable {
    case liveSource(URL)
    case persistedManifest(VaultManifest, VaultProjectionSupplement?)
    case minimum
}

public struct VaultWriteAdmissionRequest: Equatable, Sendable {
    public let target: VaultWriteTarget
    public let sourceURL: URL?
    public let targetRootURL: URL
    public let minimumProjectedBytes: Int64
    public let manifest: VaultManifest?
    public let projection: VaultWriteProjection

    public init(
        target: VaultWriteTarget,
        sourceURL: URL?,
        targetRootURL: URL,
        minimumProjectedBytes: Int64,
        manifest: VaultManifest? = nil,
        projection: VaultWriteProjection? = nil
    ) {
        self.target = target
        self.sourceURL = sourceURL
        self.targetRootURL = targetRootURL
        self.minimumProjectedBytes = minimumProjectedBytes
        self.manifest = manifest
        self.projection = projection
            ?? manifest.map { .persistedManifest($0, nil) }
            ?? sourceURL.map(VaultWriteProjection.liveSource)
            ?? .minimum
    }
}

public enum VaultWriteAdmissionError: Error, LocalizedError, Equatable, Sendable {
    case postponed(VaultAutomationPostponement)

    public var errorDescription: String? {
        switch self {
        case .postponed(let reason): reason.message
        }
    }
}

public actor LocalVaultTransferEngine {
    public typealias FaultInjector = @Sendable (VaultTransferFaultPoint, VaultTransferRecord) throws -> Void
    public typealias WriteOperation = @Sendable () async throws -> Void
    public typealias WriteAdmission = @Sendable (VaultWriteAdmissionRequest, WriteOperation) async throws -> Void
    public typealias RemovalAdmission = @Sendable (VaultTransferRecord) async throws -> Void
    public typealias VolumeIdentifier = @Sendable (URL) throws -> UInt64

    private let activeRoot: URL
    private let archiveRoot: URL
    private let store: any VaultTransferStoring
    private let provider: any ArchiveStorageProvider
    private let fileManager: FileManager
    private let manifestBuilder: VaultManifestBuilder
    private let faultInjector: FaultInjector?
    private let now: @Sendable () -> Date
    private let recoveryPolicy: VaultTransferRecoveryPolicy
    private let writeAdmission: WriteAdmission
    private let removalAdmission: RemovalAdmission
    private let volumeIdentifier: VolumeIdentifier

    public init(
        activeRoot: URL,
        archiveRoot: URL,
        store: any VaultTransferStoring,
        provider: (any ArchiveStorageProvider)? = nil,
        fileManager: FileManager = .default,
        faultInjector: FaultInjector? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        recoveryPolicy: VaultTransferRecoveryPolicy = .production,
        writeAdmission: @escaping WriteAdmission = { _, _ in
            throw LocalVaultTransferError.writeAdmissionRequired
        },
        removalAdmission: @escaping RemovalAdmission = { _ in
            throw LocalVaultTransferError.removalAdmissionRequired
        },
        volumeIdentifier: VolumeIdentifier? = nil
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
        self.recoveryPolicy = recoveryPolicy
        self.writeAdmission = writeAdmission
        self.removalAdmission = removalAdmission
        self.volumeIdentifier = volumeIdentifier ?? Self.foundationVolumeIdentifier
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
        record.updatedAt = now()
        switch try store.claimTransfer(record) {
        case .claimed:
            break
        case .existing:
            throw LocalVaultTransferError.transferAlreadyOwned
        }
        try advance(&record, to: .archiveEligible)
        return try await execute(record)
    }

    /// Relaunch entry point. Incomplete records are resumed idempotently before
    /// callers schedule any new work.
    @discardableResult
    public func recoverAtLaunch() async -> [VaultTransferRecord] {
        guard let allRecords = try? store.allTransferRecords() else { return [] }
        var records = (try? store.recoverableRecords()) ?? []
        let verifiedSurvivors = Dictionary(grouping: allRecords.filter {
            VaultTransferOwnershipPolicy.isVerifiedTerminal($0.state)
        }, by: \.projectID).compactMapValues { records in
            records.max(by: Self.isEarlierVerifiedSurvivor)
        }
        var usableVerifiedSurvivors: [ProjectID: VaultTransferRecord] = [:]
        for (projectID, survivor) in verifiedSurvivors {
            // Verification can read gigabytes. It is needed here only if this
            // generation could retire an older incomplete transfer for its song.
            guard records.contains(where: {
                $0.projectID == projectID && Self.isCausallyOlder($0, than: survivor)
            }) else { continue }
            if await hasUsableVerifiedArchiveGeneration(survivor) {
                usableVerifiedSurvivors[projectID] = survivor
            }
        }
        for var record in records {
            guard let survivor = usableVerifiedSurvivors[record.projectID],
                  Self.isCausallyOlder(record, than: survivor) else { continue }
            record.state = .superseded
            record.supersededBy = survivor.id
            record.error = nil
            record.nextRetryAt = nil
            do {
                try persist(&record)
            } catch {
                continue
            }
        }
        records.removeAll { record in
            (try? store.record(id: record.id)?.state) == .superseded
        }
        // A failed automatic attempt used to create a fresh transfer every minute.
        // Resume only the newest record for each project so launch recovery cannot
        // replay several full-project copies and hashes for the same source.
        let newestRecords = VaultTransferRecoveryPolicy.candidates(from: records)
        var results: [VaultTransferRecord] = []
        for var record in newestRecords {
            if needsLegacyMetadataMigration(record) {
                do {
                    try migrateLegacyMetadataFiles(&record)
                } catch {
                    results.append(record)
                    continue
                }
            }
            if record.state == .failedRecoverable {
                guard let origin = record.error?.origin,
                      VaultTransferRetryPolicy.permitsNondestructiveArchiveOrigin(origin) else {
                    results.append(record)
                    continue
                }
            }
            if record.state == .removingActiveCopy || record.state == .evictingProviderCache {
                let persistedDestructivePhase = record
                let origin = record.state
                record.state = .recoveryRequired
                record.error = VaultTransferError(
                    origin: origin,
                    reason: .unknown,
                    message: origin == .removingActiveCopy
                        ? "Launch recovery stopped before Active-copy removal could be confirmed. Existing copies were preserved for review."
                        : "Launch recovery stopped before provider-cache eviction could be confirmed. Existing copies were preserved for review."
                )
                record.nextRetryAt = nil
                do {
                    try persist(&record)
                    results.append(record)
                } catch {
                    results.append(persistedDestructivePhase)
                }
                continue
            }
            if record.state == .failedRecoverable,
               !recoveryPolicy.permitsAutomaticAttempt(for: record, at: now()) {
                results.append(record)
                continue
            }
            if record.state == .failedRecoverable, let origin = record.error?.origin {
                let persistedFailure = record
                record.state = origin
                record.error = nil
                record.nextRetryAt = nil
                do {
                    try persist(&record)
                } catch {
                    results.append(persistedFailure)
                    continue
                }
            }
            do { results.append(try await execute(record)) }
            catch is VaultTransferInterruption { results.append((try? store.record(id: record.id)) ?? record) }
            catch { results.append((try? store.record(id: record.id)) ?? record) }
        }
        return results
    }

    /// Explicit user-authorized retry path for records that reached the automatic
    /// attempt ceiling. This performs one attempt without weakening write admission
    /// or deleting the persisted staging copy on failure.
    @discardableResult
    public func retryRecoverableTransfer(id: UUID) async -> VaultTransferRecord? {
        guard var record = try? store.record(id: id),
              record.state == .failedRecoverable,
              let origin = record.error?.origin,
              VaultTransferRetryPolicy.permitsNondestructiveArchiveOrigin(origin) else { return nil }
        let recopy: Bool
        do {
            recopy = try await preparePortableArchiveRetry(&record)
        } catch {
            record.error = VaultTransferError(origin: origin, reason: failureReason(for: error), message: error.localizedDescription)
            try? persist(&record)
            return record
        }
        do {
            record.state = recopy ? .copyingToArchiveStaging : origin
            record.error = nil
            record.nextRetryAt = nil
            try persist(&record)
            return try await execute(record)
        } catch is VaultTransferInterruption {
            return (try? store.record(id: record.id)) ?? record
        } catch {
            return (try? store.record(id: record.id)) ?? record
        }
    }

    /// Rebuild legacy provider-incompatible staging only on explicit retry and
    /// only while the complete original source still matches its saved hashes.
    /// Retain the failed tree; never reinterpret a provider-renamed path as proof.
    private func preparePortableArchiveRetry(_ record: inout VaultTransferRecord) async throws -> Bool {
        guard let manifest = record.manifest, manifest.archiveLayout == nil,
              manifest.preparedForArchive().archiveLayout != nil else { return false }
        try validatePaths(record)
        guard record.manifestID == manifest.id, record.supersededBy == nil else {
            throw LocalVaultTransferError.missingPersistedArchiveEvidence
        }
        try manifest.validatePersistedContentEnvelope()
        let observed = try manifestBuilder.build(at: record.sourceURL)
        guard manifest.hasSameImmutableContent(as: observed) else { throw LocalVaultTransferError.sourceMutated }
        // Promotion recovery must not abandon a generation that already exists.
        guard !fileManager.fileExists(atPath: record.destinationURL.path) else {
            throw LocalVaultTransferError.occupiedDestination
        }
        if fileManager.fileExists(atPath: record.stagingURL.path) {
            let retained = record.stagingURL.deletingLastPathComponent()
                .appendingPathComponent("\(record.id.uuidString.lowercased())-legacy-\(UUID().uuidString.lowercased())", isDirectory: true)
            record.preservedArchiveCopies = (record.preservedArchiveCopies ?? []) + [retained]
            try persist(&record)
            let transfer = record
            let activeRoot = self.activeRoot
            let archiveRoot = self.archiveRoot
            let manager = VaultSendableFileManager(fileManager)
            try await writeAdmission(VaultWriteAdmissionRequest(
                target: .archive, sourceURL: record.sourceURL,
                targetRootURL: archiveRoot, minimumProjectedBytes: manifest.totalBytes
            )) {
                try Self.validatePaths(transfer, activeRoot: activeRoot, archiveRoot: archiveRoot)
                guard PathSafety(fileManager: manager.value).isResolvedContainedWithoutNestedSymlinks(retained, in: archiveRoot),
                      !manager.value.fileExists(atPath: retained.path) else {
                    throw LocalVaultTransferError.unsafeStagingPath
                }
                try manager.value.moveItem(at: transfer.stagingURL, to: retained)
            }
        }
        record.durability = nil
        record.projectionSupplement = nil
        return true
    }

    /// Explicit user recovery only. Never resumes removal: preserve any surviving
    /// Active directory, then make the freshly verified archive restorable again.
    public func recoverInterruptedRemoval(id: UUID) async throws -> VaultTransferRecord {
        guard var record = try store.record(id: id), record.state == .recoveryRequired,
              let origin = record.error?.origin,
              [.removingActiveCopy, .evictingProviderCache].contains(origin),
              record.supersededBy == nil, let manifest = record.manifest,
              record.manifestID == manifest.id, record.durability != nil else {
            throw LocalVaultTransferError.missingPersistedArchiveEvidence
        }
        try validatePaths(record)
        let destination = record.destinationURL
        let expectedGeneration = archiveRoot.appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(record.projectID.description, isDirectory: true)
            .appendingPathComponent("generation-\(record.id.uuidString.lowercased())", isDirectory: true)
        guard destination.standardizedFileURL.resolvingSymlinksInPath() == expectedGeneration.standardizedFileURL.resolvingSymlinksInPath() else {
            throw LocalVaultTransferError.unsafeDestinationPath
        }
        if try await provider.currentLocality(at: destination, manifest: manifest) != .fullyLocalCurrent {
            let provider = self.provider
            try await writeAdmission(VaultWriteAdmissionRequest(
                target: .archive, sourceURL: nil, targetRootURL: archiveRoot,
                minimumProjectedBytes: manifest.totalBytes, manifest: manifest
            )) { try await provider.materialize(destination, manifest: manifest) }
        }
        try await provider.prepareForRead(destination)
        try validatePaths(record)
        try manifestBuilder.verifyArchive(manifest, at: destination)
        if fileManager.fileExists(atPath: record.sourceURL.path) {
            let binding = try SourceRootFileSystemBinding(opening: record.sourceURL)
            let preserved = activeRoot.appendingPathComponent(".niko-recovery", isDirectory: true)
                .appendingPathComponent(record.id.uuidString.lowercased(), isDirectory: true)
                .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
                .appendingPathComponent(record.sourceURL.lastPathComponent, isDirectory: true)
            record.preservedActiveCopies = (record.preservedActiveCopies ?? []) + [preserved]
            // Persist the preservation destination before moving anything. A crash
            // on either side of the move leaves both paths available for review.
            try persist(&record)
            let recoveryRecord = record
            let expectedIdentity = binding.identity
            try await removalAdmission(record)
            try await writeAdmission(VaultWriteAdmissionRequest(
                target: .active, sourceURL: nil, targetRootURL: activeRoot,
                minimumProjectedBytes: manifest.totalBytes, manifest: manifest
            )) {
                try await self.preserveActiveForRecovery(
                    recoveryRecord, at: preserved, expectedIdentity: expectedIdentity
                )
            }
            withExtendedLifetime(binding) {}
        }
        try validatePaths(record)
        guard !fileManager.fileExists(atPath: record.sourceURL.path) else {
            throw LocalVaultTransferError.occupiedDestination
        }
        try manifestBuilder.verifyArchive(manifest, at: destination)
        record.state = .archiveVerified
        record.error = nil
        record.nextRetryAt = nil
        try persist(&record)
        return record
    }

    private func preserveActiveForRecovery(
        _ record: VaultTransferRecord, at preserved: URL, expectedIdentity: SourceFileSystemIdentity
    ) throws {
        try validatePaths(record)
        let safety = PathSafety()
        guard safety.isResolvedContainedWithoutNestedSymlinks(preserved, in: activeRoot),
              safety.isResolvedContainedWithoutNestedSymlinks(record.sourceURL, in: activeRoot),
              try Self.sourceFileSystemIdentity(at: record.sourceURL) == expectedIdentity,
              !fileManager.fileExists(atPath: preserved.path), let manifest = record.manifest else {
            throw LocalVaultTransferError.unsafeDestinationPath
        }
        try manifestBuilder.verifyArchive(manifest, at: record.destinationURL)
        try fileManager.createDirectory(at: preserved.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard safety.isResolvedContainedWithoutNestedSymlinks(preserved, in: activeRoot),
              try Self.sourceFileSystemIdentity(at: record.sourceURL) == expectedIdentity else {
            throw LocalVaultTransferError.sourceMutated
        }
        try fileManager.moveItem(at: record.sourceURL, to: preserved)
    }

    /// Removes the Active copy only after independently reloading the terminal
    /// archive record and re-verifying its manifest. Automatic callers should
    /// perform their final activity/open-file probe immediately before calling.
    @discardableResult
    public func removeActiveCopy(after archivedRecord: VaultTransferRecord) async throws -> VaultTransferRecord {
        guard
            VaultTransferOwnershipPolicy.isVerifiedTerminal(archivedRecord.state),
            let persisted = try store.record(id: archivedRecord.id),
            persisted.state == archivedRecord.state,
            persisted.projectID == archivedRecord.projectID,
            persisted.destinationURL == archivedRecord.destinationURL,
            persisted.manifestID == archivedRecord.manifestID,
            let manifest = persisted.manifest,
            let durability = persisted.durability
        else {
            throw LocalVaultTransferError.missingPersistedArchiveEvidence
        }
        try manifestBuilder.verifyArchive(manifest, at: persisted.destinationURL)
        var record = persisted
        // A restored project can reuse an earlier archived generation. Fresh
        // manifest verification above re-establishes its removal evidence.
        record.state = .archiveVerified
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
        var removalAdmissionDenied = false
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
                    let provider = self.provider
                    let archiveRoot = self.archiveRoot
                    let activeRoot = self.activeRoot
                    let preparingRecord = record
                    try await writeAdmission(VaultWriteAdmissionRequest(
                        target: .archive,
                        sourceURL: preparingRecord.sourceURL,
                        targetRootURL: archiveRoot,
                        minimumProjectedBytes: 0
                    )) {
                        try Self.validatePaths(
                            preparingRecord,
                            activeRoot: activeRoot,
                            archiveRoot: archiveRoot
                        )
                        try await provider.prepareForWrite(at: archiveRoot)
                    }
                    try advance(&record, to: .copyingToArchiveStaging)
                case .copyingToArchiveStaging:
                    try inject(.copyingToArchiveStaging, record)
                    try await copyToStaging(&record)
                    try advance(&record, to: .verifyingArchiveStaging)
                case .verifyingArchiveStaging:
                    try inject(.verifyingArchiveStaging, record)
                    guard let manifest = record.manifest else { throw LocalVaultTransferError.missingManifest }
                    try manifestBuilder.verifyArchive(manifest, at: record.stagingURL)
                    try advance(&record, to: .awaitingProviderDurability)
                case .awaitingProviderDurability:
                    try inject(.awaitingProviderDurability, record)
                    record.durability = try await provider.waitUntilDurable(record.stagingURL)
                    try persist(&record)
                    try advance(&record, to: .promotingArchiveGeneration)
                case .promotingArchiveGeneration:
                    try inject(.promotingArchiveGeneration, record)
                    try await promote(&record)
                    // The provider barrier before promotion covers the staged
                    // bytes. The final rename is another provider-visible
                    // mutation, so it must also become durable before this
                    // generation can authorize removal of the Active copy.
                    let finalDurability = try await provider.waitUntilDurable(record.destinationURL)
                    // Provider coordination is an await boundary at which a
                    // synced folder may replace or mutate the promoted tree.
                    // Revalidate both containment and exact content immediately
                    // before persisting any terminal durability/success claim.
                    try validatePaths(record)
                    guard let manifest = record.manifest else {
                        throw LocalVaultTransferError.missingManifest
                    }
                    try manifestBuilder.verifyArchive(manifest, at: record.destinationURL)
                    record.durability = finalDurability
                    try persist(&record)
                    record.state = .archiveVerified
                    record.error = nil
                    record.nextRetryAt = nil
                    try persist(&record)
                    return record
                case .archiveVerified:
                    return record
                case .removingActiveCopy:
                    // Keep the verified directory object open across admission so
                    // its inode cannot be recycled into a same-path replacement.
                    let sourceBinding = try SourceRootFileSystemBinding(opening: record.sourceURL)
                    try validateRemovalEvidence(
                        record,
                        expectedSourceIdentity: sourceBinding.identity
                    )
                    do {
                        try await removalAdmission(record)
                        // Recheck after the first probe's await boundaries.
                        try await removalAdmission(record)
                    } catch {
                        // Neither admission can remove data. Keep a verified
                        // backup retryable instead of claiming partial removal.
                        removalAdmissionDenied = true
                        throw error
                    }
                    // No further await before the destructive operation.
                    try validateRemovalEvidence(
                        record,
                        expectedSourceIdentity: sourceBinding.identity
                    )
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
            record.error = VaultTransferError(origin: origin, reason: reason, message: (error as? LocalizedError)?.errorDescription ?? String(describing: error))
            let destructiveOrigin = origin == .removingActiveCopy || origin == .evictingProviderCache
            if removalAdmissionDenied {
                record.state = .archiveVerified
            } else {
                record.state = reason == .occupiedDestination || destructiveOrigin
                    ? .recoveryRequired
                    : .failedRecoverable
            }
            // Dynamic admission re-enumerates the source, so postponements consume
            // the same bounded automatic-attempt budget as provider failures.
            // Once the persisted ceiling is reached, only the explicit user path
            // can request another attempt.
            record.retryCount += 1
            record.nextRetryAt = record.state == .failedRecoverable
                ? recoveryPolicy.nextRetryDate(afterFailedAttempt: record.retryCount, at: now())
                : nil
            try persist(&record)
            throw error
        }
    }

    private func copyToStaging(_ record: inout VaultTransferRecord) async throws {
        try validatePaths(record)
        // Building the source manifest is read-only evidence collection. The
        // admission callback still re-probes capacity immediately around the
        // first destructive/new-byte staging operation below.
        let observedSource = try manifestBuilder.build(at: record.sourceURL)
        if record.preservedArchiveCopies != nil, let previous = record.manifest, previous.archiveLayout == nil {
            guard previous.hasSameImmutableContent(as: observedSource) else { throw LocalVaultTransferError.sourceMutated }
        }
        let sourceBefore = observedSource.preparedForArchive()
        let sourceURL = record.sourceURL
        let stagingURL = record.stagingURL
        let archiveRoot = self.archiveRoot
        let activeRoot = self.activeRoot
        let recordForValidation = record
        let fileManager = VaultSendableFileManager(self.fileManager)
        let volumeIdentifier = self.volumeIdentifier
        try await writeAdmission(VaultWriteAdmissionRequest(
            target: .archive,
            sourceURL: sourceURL,
            targetRootURL: archiveRoot,
            minimumProjectedBytes: sourceBefore.totalBytes
        )) {
            try Self.validatePaths(
                recordForValidation,
                activeRoot: activeRoot,
                archiveRoot: archiveRoot
            )
            guard try volumeIdentifier(stagingURL.deletingLastPathComponent())
                    == volumeIdentifier(archiveRoot) else {
                throw LocalVaultTransferError.writeTargetVolumeMismatch
            }
            if fileManager.value.fileExists(atPath: stagingURL.path) {
                guard Self.contains(archiveRoot.appendingPathComponent(".niko-staging", isDirectory: true), stagingURL) else {
                    throw LocalVaultTransferError.unsafeStagingPath
                }
                try fileManager.value.removeItem(at: stagingURL)
            }
            try fileManager.value.createDirectory(at: stagingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if sourceBefore.archiveLayout != nil {
                try VaultManifestCopier.copy(sourceBefore, from: sourceURL, to: stagingURL, fileManager: fileManager.value, toArchive: true)
            } else {
                try fileManager.value.copyItem(at: sourceURL, to: stagingURL)
            }
            try Self.removeIgnoredMetadataFiles(
                below: stagingURL,
                fileManager: fileManager.value
            )
        }
        let sourceAfter = try manifestBuilder.build(at: record.sourceURL, id: sourceBefore.id, createdAt: sourceBefore.createdAt)
        guard sourceBefore.entries == sourceAfter.entries else { throw LocalVaultTransferError.sourceMutated }
        record.manifestID = sourceBefore.id
        record.manifest = sourceBefore
        record.totalBytes = sourceBefore.totalBytes
        record.completedBytes = sourceBefore.totalBytes
        try persist(&record)
    }

    private func needsLegacyMetadataMigration(_ record: VaultTransferRecord) -> Bool {
        let resumesAtDurability = record.state == .awaitingProviderDurability
            || (record.state == .failedRecoverable
                && record.error?.origin == .awaitingProviderDurability)
        guard resumesAtDurability, let manifest = record.manifest else { return false }
        return manifest.entries.contains { entry in
            entry.type == .regularFile
                && VaultArchiveContentPolicy.ignoresRegularFile(
                    relativePath: entry.relativePath
                )
        }
    }

    /// Transfers created before exact `.DS_Store` exclusion persisted those
    /// Finder metadata files as archive content. Verify every substantive byte
    /// against that legacy manifest before removing only the metadata files,
    /// then persist a fresh manifest before any provider or promotion step.
    private func migrateLegacyMetadataFiles(_ record: inout VaultTransferRecord) throws {
        try validatePaths(record)
        guard let legacyManifest = record.manifest,
              fileManager.fileExists(atPath: record.stagingURL.path) else {
            throw VaultManifestError.missingRoot
        }
        let substantiveManifest = VaultManifest(
            id: legacyManifest.id,
            createdAt: legacyManifest.createdAt,
            entries: legacyManifest.entries.filter { entry in
                entry.type != .regularFile
                    || !VaultArchiveContentPolicy.ignoresRegularFile(
                        relativePath: entry.relativePath
                    )
            },
            rootAllocatedByteCount: legacyManifest.rootAllocatedByteCount,
            rootExtendedAttributeBytes: legacyManifest.rootExtendedAttributeBytes
        )
        try substantiveManifest.validatePersistedContentEnvelope()
        try manifestBuilder.verify(substantiveManifest, at: record.stagingURL)
        try Self.removeIgnoredMetadataFiles(
            below: record.stagingURL,
            fileManager: fileManager
        )
        let migratedManifest = try manifestBuilder.build(
            at: record.stagingURL,
            createdAt: now()
        )
        guard substantiveManifest.hasSameImmutableContent(as: migratedManifest) else {
            throw VaultManifestError.mismatch
        }
        try manifestBuilder.verify(migratedManifest, at: record.stagingURL)
        record.manifestID = migratedManifest.id
        record.manifest = migratedManifest
        record.projectionSupplement = nil
        record.totalBytes = migratedManifest.totalBytes
        record.completedBytes = migratedManifest.totalBytes
        record.durability = nil
        record.retryCount = 0
        record.nextRetryAt = nil
        try persist(&record)
    }

    private static func removeIgnoredMetadataFiles(
        below root: URL,
        fileManager: FileManager
    ) throws {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        var enumerationFailure: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, error in
                enumerationFailure = error
                return false
            }
        ) else {
            throw VaultManifestError.missingRoot
        }
        var metadataFiles: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  VaultArchiveContentPolicy.ignoresRegularFile(at: url) else {
                continue
            }
            guard PathSafety().isResolvedContainedWithoutNestedSymlinks(url, in: root),
                  url.standardizedFileURL != root.standardizedFileURL else {
                throw LocalVaultTransferError.unsafeStagingPath
            }
            metadataFiles.append(url)
        }
        if let enumerationFailure { throw enumerationFailure }
        for url in metadataFiles {
            try fileManager.removeItem(at: url)
        }
    }

    private func promote(_ record: inout VaultTransferRecord) async throws {
        try validatePaths(record)
        guard let manifest = record.manifest else { throw LocalVaultTransferError.missingManifest }
        let destinationExists = fileManager.fileExists(atPath: record.destinationURL.path)
        let stagingExists = fileManager.fileExists(atPath: record.stagingURL.path)
        if destinationExists {
            guard !stagingExists else { throw LocalVaultTransferError.occupiedDestination }
            // A previous rename completed before process termination. Verify it
            // rather than overwrite or create a second generation.
            try manifestBuilder.verifyArchive(manifest, at: record.destinationURL)
            return
        }
        guard stagingExists else { throw VaultManifestError.missingRoot }
        let destinationParent = record.destinationURL.deletingLastPathComponent()
        let stagingVolume = try volumeIdentifier(record.stagingURL)
        let destinationVolume = try volumeIdentifier(destinationParent)
        if stagingVolume == destinationVolume {
            try validatePaths(record)
            try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
            try fileManager.moveItem(at: record.stagingURL, to: record.destinationURL)
        } else {
            throw LocalVaultTransferError.crossVolumePromotion
        }
        try manifestBuilder.verifyArchive(manifest, at: record.destinationURL)
    }

    private func validatePaths(_ record: VaultTransferRecord) throws {
        try Self.validatePaths(record, activeRoot: activeRoot, archiveRoot: archiveRoot)
    }

    private static func validatePaths(
        _ record: VaultTransferRecord,
        activeRoot: URL,
        archiveRoot: URL
    ) throws {
        let stagingRoot = archiveRoot.appendingPathComponent(".niko-staging", isDirectory: true)
        let generationsRoot = archiveRoot.appendingPathComponent("generations", isDirectory: true)
        let safety = PathSafety()
        guard safety.isResolvedContainedWithoutNestedSymlinks(stagingRoot, in: archiveRoot),
              stagingRoot != archiveRoot else {
            throw LocalVaultTransferError.unsafeStagingPath
        }
        guard safety.isResolvedContainedWithoutNestedSymlinks(generationsRoot, in: archiveRoot),
              generationsRoot != archiveRoot else {
            throw LocalVaultTransferError.unsafeDestinationPath
        }
        guard safety.isResolvedContained(record.sourceURL, in: [activeRoot]),
              record.sourceURL != activeRoot else {
            throw LocalVaultTransferError.sourceOutsideActiveRoot
        }
        guard safety.isResolvedContainedWithoutNestedSymlinks(record.stagingURL, in: stagingRoot),
              record.stagingURL != stagingRoot else {
            throw LocalVaultTransferError.unsafeStagingPath
        }
        guard safety.isResolvedContainedWithoutNestedSymlinks(record.destinationURL, in: generationsRoot),
              record.destinationURL != generationsRoot else {
            throw LocalVaultTransferError.unsafeDestinationPath
        }
    }

    private func validateRemovalEvidence(
        _ record: VaultTransferRecord,
        expectedSourceIdentity: SourceFileSystemIdentity
    ) throws {
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
        try manifestBuilder.verifyArchive(manifest, at: persisted.destinationURL)
        // Bind manifest verification to one concrete source-root filesystem
        // object. Content-identical path replacement must still be retained for
        // manual review rather than inheriting deletion authorization.
        do {
            let identityBeforeVerification = try Self.sourceFileSystemIdentity(at: persisted.sourceURL)
            guard identityBeforeVerification == expectedSourceIdentity else {
                throw LocalVaultTransferError.sourceMutated
            }
            try manifestBuilder.verify(manifest, at: persisted.sourceURL)
            let identityAfterVerification = try Self.sourceFileSystemIdentity(at: persisted.sourceURL)
            guard identityAfterVerification == expectedSourceIdentity else {
                throw LocalVaultTransferError.sourceMutated
            }
        } catch {
            throw LocalVaultTransferError.sourceMutated
        }
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
        case VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity),
             VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable),
             VaultWriteAdmissionError.postponed(.invalidPolicy): .insufficientSpace
        case VaultManifestError.mismatch: .integrityMismatch
        case LocalFolderStorageError.unreadable, LocalFolderStorageError.unwritable: .permissionLost
        case FileProviderArchiveStorageError.durabilityUnavailable: .providerUnsynced
        case FileProviderArchiveStorageError.operationTimedOut: .slowProviderSync
        case FileProviderArchiveStorageError.lookupUnavailable,
             FileProviderArchiveStorageError.domainUnavailable,
             FileProviderArchiveStorageError.domainDisabled,
             FileProviderArchiveStorageError.domainDisconnected,
             FileProviderArchiveStorageError.managerUnavailable: .providerOffline
        default: .unknown
        }
    }

    private static func contains(_ root: URL, _ candidate: URL) -> Bool {
        PathSafety().isResolvedContained(candidate, in: [root])
    }

    static func foundationVolumeIdentifier(at url: URL) throws -> UInt64 {
        var candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        while !FileManager.default.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else {
                throw LocalVaultTransferError.unsafeDestinationPath
            }
            candidate = parent
        }
        var information = stat()
        let result = candidate.path.withCString { Darwin.lstat($0, &information) }
        guard result == 0 else { throw LocalVaultTransferError.unsafeDestinationPath }
        return UInt64(information.st_dev)
    }

    private static func sourceFileSystemIdentity(at url: URL) throws -> SourceFileSystemIdentity {
        var information = stat()
        let result = url.path.withCString { Darwin.lstat($0, &information) }
        guard result == 0,
              (information.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw LocalVaultTransferError.sourceMutated
        }
        return SourceFileSystemIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }

    /// Terminal supersession is a causal relationship, so mutable retry or
    /// presentation timestamps must never decide which verified generation is
    /// the successor. Creation ties are ordered only to select one survivor for
    /// validation; the strict causal check below still fails closed on a tie.
    private static func isEarlierVerifiedSurvivor(
        _ lhs: VaultTransferRecord,
        _ rhs: VaultTransferRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func isCausallyOlder(
        _ candidate: VaultTransferRecord,
        than verifiedSuccessor: VaultTransferRecord
    ) -> Bool {
        candidate.createdAt < verifiedSuccessor.createdAt
    }

    private func hasUsableVerifiedArchiveGeneration(_ record: VaultTransferRecord) async -> Bool {
        guard VaultTransferOwnershipPolicy.isVerifiedTerminal(record.state),
              let manifestID = record.manifestID,
              let manifest = record.manifest,
              manifest.id == manifestID,
              (try? manifest.validatePersistedContentEnvelope()) != nil,
              hasPersistedGenerationPath(record) else { return false }
        if record.state == .archivedOnlineOnly {
            guard record.durability == .syncedToProvider
                    || record.durability == .independentlyBackedUp else { return false }
            do {
                switch try await provider.currentLocality(
                    at: record.destinationURL,
                    manifest: manifest
                ) {
                case .fullyLocalCurrent, .materializationRequired:
                    return true
                case .unknown:
                    return false
                }
            } catch {
                return false
            }
        }
        guard fileManager.fileExists(atPath: record.destinationURL.path) else { return false }
        do {
            try manifestBuilder.verifyArchive(manifest, at: record.destinationURL)
            return true
        } catch {
            return false
        }
    }

    private func hasPersistedGenerationPath(_ record: VaultTransferRecord) -> Bool {
        let expectedDestination = archiveRoot
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(record.projectID.description, isDirectory: true)
            .appendingPathComponent(
                "generation-\(record.id.uuidString.lowercased())",
                isDirectory: true
            )
        guard record.destinationURL.isFileURL,
              expectedDestination.isFileURL,
              Self.normalizedAuthority(of: record.destinationURL)
                == Self.normalizedAuthority(of: expectedDestination) else {
            return false
        }
        let projectRoot = expectedDestination
            .deletingLastPathComponent()
            .standardizedFileURL
            .pathComponents
        let destination = record.destinationURL.standardizedFileURL.pathComponents
        return destination.count == projectRoot.count + 1
            && Array(destination.prefix(projectRoot.count)) == projectRoot
            && destination.last == "generation-\(record.id.uuidString.lowercased())"
    }

    private struct URLAuthority: Equatable {
        let user: String
        let password: String
        let host: String
        let port: Int?
    }

    private static func normalizedAuthority(of url: URL) -> URLAuthority {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return URLAuthority(
            user: components?.user ?? "",
            password: components?.password ?? "",
            host: (components?.host ?? "").lowercased(),
            port: components?.port
        )
    }

}

private struct SourceFileSystemIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
}

private final class SourceRootFileSystemBinding {
    let identity: SourceFileSystemIdentity
    private let descriptor: Int32

    init(opening url: URL) throws {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw LocalVaultTransferError.sourceMutated
        }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              (information.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            Darwin.close(descriptor)
            throw LocalVaultTransferError.sourceMutated
        }

        self.descriptor = descriptor
        self.identity = SourceFileSystemIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }

    deinit {
        Darwin.close(descriptor)
    }
}

private struct VaultSendableFileManager: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}
