import Foundation

public enum VaultRestoreFaultPoint: String, CaseIterable, Sendable {
    case materializingArchive
    case copyingToActiveStaging
    case verifyingActiveStaging
    case promotingActiveCopy
    case persistingActiveLocation
    case openingInCubase
}

public enum LocalVaultRestoreError: LocalizedError, Equatable, Sendable {
    case archiveGenerationNotFound
    case archiveGenerationNotVerified
    case missingManifest
    case invalidDestination
    case unsafeStagingPath
    case occupiedDestination
    case noSupportedProject
    case restoreAlreadyInProgress
    case crossVolumePromotion
    case writeTargetVolumeMismatch
    case unsafeArchiveGenerationPath
    case archiveLocalityUnavailable
    case archiveContentsChanged(String)
    case legacyProjectionIdentityMismatch
    case archiveTransferBindingUnavailable
    case activeDestinationIntegrityMismatch

    public var errorDescription: String? {
        switch self {
        case .archiveContentsChanged(let detail):
            "Archive verification failed: \(detail) The archive was kept. Review the changed file before restoring."
        case .archiveLocalityUnavailable:
            "The archive provider could not confirm that the verified files are available locally. Check the provider's download status before retrying."
        default:
            "Restore stopped safely: \(String(describing: self))."
        }
    }

    static func fromLocalityFailure(_ error: Error) -> LocalVaultRestoreError {
        switch error {
        case FileProviderArchiveStorageError.expectedFileSizeMismatch(let url, let expected, let actual):
            .archiveContentsChanged("\(url.lastPathComponent) changed from \(expected) to \(actual) bytes since verification.")
        case FileProviderArchiveStorageError.expectedItemMismatch:
            .archiveContentsChanged("An archive item no longer matches the recorded file type or size.")
        default:
            .archiveLocalityUnavailable
        }
    }
}

public struct SafeVaultProjectOpener: VaultProjectOpening, @unchecked Sendable {
    private let opener: MusicItemOpener
    private let detector: ProjectVersionDetector

    public init(workspace: (any WorkspaceOpening)? = nil, fileManager: FileManager = .default) {
        opener = MusicItemOpener(workspace: workspace)
        detector = ProjectVersionDetector(fileManager: fileManager)
    }

    public func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult? {
        let versions = try detector.detectVersions(in: projectURL)
        guard let latest = detector.latestProject(from: versions) else { throw LocalVaultRestoreError.noSupportedProject }
        let song = Song(
            folderPath: projectURL,
            originalFolderName: projectURL.lastPathComponent,
            displayTitle: projectURL.lastPathComponent,
            projectVersions: versions,
            latestCPR: latest
        )
        return try opener.openLatestCPR(for: song, dryRun: false, allowedRoots: [allowedRoot])
    }
}

public actor LocalVaultRestoreEngine {
    public typealias FaultInjector = @Sendable (VaultRestoreFaultPoint, VaultRestoreRecord) throws -> Void

    private let activeRoot: URL
    private let archiveRoot: URL?
    private let activeRootID: UUID
    private let resolver: any VaultArchiveGenerationResolving
    private let store: any VaultRestoreStoring
    private let projectionStore: (any VaultProjectionSupplementStoring)?
    private let provider: any ArchiveStorageProvider
    private let catalog: any ActiveProjectLocationPersisting
    private let projectOpener: any VaultProjectOpening
    private let fileManager: FileManager
    private let manifestBuilder: VaultManifestBuilder
    private let faultInjector: FaultInjector?
    private let now: @Sendable () -> Date
    private let writeAdmission: LocalVaultTransferEngine.WriteAdmission
    private let volumeIdentifier: LocalVaultTransferEngine.VolumeIdentifier

    public init(
        activeRoot: URL,
        archiveRoot: URL? = nil,
        activeRootID: UUID,
        resolver: any VaultArchiveGenerationResolving,
        store: any VaultRestoreStoring,
        projectionStore: (any VaultProjectionSupplementStoring)? = nil,
        provider: any ArchiveStorageProvider,
        catalog: any ActiveProjectLocationPersisting,
        projectOpener: any VaultProjectOpening,
        fileManager: FileManager = .default,
        faultInjector: FaultInjector? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        writeAdmission: @escaping LocalVaultTransferEngine.WriteAdmission = { _, _ in
            throw LocalVaultTransferError.writeAdmissionRequired
        },
        volumeIdentifier: LocalVaultTransferEngine.VolumeIdentifier? = nil,
        manifestBuilder: VaultManifestBuilder? = nil
    ) {
        self.activeRoot = activeRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.archiveRoot = archiveRoot?.standardizedFileURL.resolvingSymlinksInPath()
        self.activeRootID = activeRootID
        self.resolver = resolver
        self.store = store
        self.projectionStore = projectionStore
        self.provider = provider
        self.catalog = catalog
        self.projectOpener = projectOpener
        self.fileManager = fileManager
        self.manifestBuilder = manifestBuilder ?? VaultManifestBuilder(fileManager: fileManager)
        self.faultInjector = faultInjector
        self.now = now
        self.writeAdmission = writeAdmission
        self.volumeIdentifier = volumeIdentifier ?? LocalVaultTransferEngine.foundationVolumeIdentifier
    }

    @discardableResult
    public func restoreAndOpen(projectID: ProjectID, destinationRelativePath: String) async throws -> VaultRestoreRecord {
        let destination = try destinationURL(relativePath: destinationRelativePath)
        guard let archive = try resolver.verifiedArchiveGeneration(projectID: projectID) else {
            throw LocalVaultRestoreError.archiveGenerationNotFound
        }
        guard [.archiveVerified, .archivedLocal, .archivedOnlineOnly].contains(archive.state) else {
            throw LocalVaultRestoreError.archiveGenerationNotVerified
        }
        try validateArchiveGeneration(archive.destinationURL)
        guard let manifest = archive.manifest else { throw LocalVaultRestoreError.missingManifest }
        let id = UUID()
        let staging = activeRoot
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        var record = VaultRestoreRecord(
            id: id,
            projectID: projectID,
            archiveGenerationURL: archive.destinationURL,
            stagingURL: staging,
            destinationURL: destination,
            manifest: manifest,
            archiveTransferID: archive.id,
            archiveTransferState: archive.state,
            requiresArchiveMaterialization: archive.state == .archivedOnlineOnly,
            projectionSupplement: archive.projectionSupplement,
            createdAt: now()
        )
        record.updatedAt = now()
        switch try store.claimRestore(record) {
        case .claimed:
            break
        case .existing:
            throw LocalVaultRestoreError.restoreAlreadyInProgress
        }
        return try await execute(record, requiresArchiveTransferBinding: false)
    }

    @discardableResult
    public func recoverAtLaunch() async -> [VaultRestoreRecord] {
        // Reconciliation is a persistence barrier: every legacy duplicate loser
        // is terminally retired before any owner can reach a provider or byte
        // side effect. A failed transaction yields no executable records.
        guard let records = try? store.reconcileRestoreRecordsForRecovery() else { return [] }
        var results: [VaultRestoreRecord] = []
        for record in records where record.failureReason == nil {
            do {
                results.append(try await execute(record, requiresArchiveTransferBinding: true))
            }
            catch is VaultTransferInterruption { results.append((try? store.restoreRecord(id: record.id)) ?? record) }
            catch { results.append((try? store.restoreRecord(id: record.id)) ?? record) }
        }
        return results
    }

    @discardableResult
    public func retryRestore(id: UUID) async throws -> VaultRestoreRecord {
        guard let record = try store.restoreRecord(id: id),
              record.completedAt == nil,
              record.phase != .superseded,
              record.supersededBy == nil else {
            throw LocalVaultRestoreError.archiveGenerationNotFound
        }
        // Keep a persisted legacy-evidence blocker until exact local verification
        // and the identity-preserving supplement CAS have both succeeded. A
        // failed manual retry must remain actionable without pretending that the
        // missing projection evidence was repaired.
        return try await execute(record, requiresArchiveTransferBinding: true)
    }

    private func execute(
        _ initial: VaultRestoreRecord,
        requiresArchiveTransferBinding: Bool
    ) async throws -> VaultRestoreRecord {
        var record = initial
        do {
            try validateArchiveGeneration(record.archiveGenerationURL)
            if requiresArchiveTransferBinding {
                try requireArchiveTransferBinding(&record)
            }
            while record.completedAt == nil {
                if requiresArchiveTransferBinding {
                    try requireArchiveTransferBinding(&record)
                }
                switch record.phase {
                case .materializingArchive:
                    try inject(.materializingArchive, record)
                    let provider = self.provider
                    let archiveURL = record.archiveGenerationURL
                    let manifest = record.manifest
                    let needsLegacySupplement = Self.requiresProjectionSupplement(manifest)
                    let locality: ArchiveStorageLocality
                    do {
                        locality = try await provider.currentLocality(
                            at: archiveURL,
                            manifest: manifest
                        )
                    } catch {
                        if needsLegacySupplement {
                            try markLegacyProjectionReview(&record)
                        }
                        throw LocalVaultRestoreError.fromLocalityFailure(error)
                    }
                    if needsLegacySupplement, locality != .fullyLocalCurrent {
                        try markLegacyProjectionReview(&record)
                        throw LocalVaultRestoreError.archiveLocalityUnavailable
                    }
                    let requiresMaterialization: Bool
                    switch locality {
                    case .fullyLocalCurrent:
                        requiresMaterialization = false
                    case .materializationRequired:
                        requiresMaterialization = true
                    case .unknown:
                        guard record.requiresArchiveMaterialization else {
                            throw LocalVaultRestoreError.archiveLocalityUnavailable
                        }
                        requiresMaterialization = true
                    }
                    if requiresMaterialization {
                        if requiresArchiveTransferBinding {
                            try requireArchiveTransferBinding(&record)
                        }
                        let materializationAdmission = VaultWriteAdmissionRequest(
                            target: .archive,
                            sourceURL: nil,
                            targetRootURL: archiveURL,
                            minimumProjectedBytes: try manifest.validatedTotalBytes(),
                            manifest: manifest
                        )
                        try await writeAdmission(materializationAdmission) {
                            try await provider.prepareForRead(archiveURL)
                        }
                        if requiresArchiveTransferBinding {
                            try requireArchiveTransferBinding(&record)
                        }
                        let archiveRoot = self.archiveRoot
                        let fileManager = VaultRestoreSendableFileManager(self.fileManager)
                        try await writeAdmission(materializationAdmission) {
                            try Self.validateArchiveGeneration(
                                archiveURL,
                                archiveRoot: archiveRoot,
                                fileManager: fileManager.value
                            )
                            try await provider.materialize(archiveURL, manifest: manifest)
                        }
                    } else {
                        try await provider.prepareForRead(archiveURL)
                    }
                    let postPrepareLocality: ArchiveStorageLocality
                    do {
                        postPrepareLocality = try await provider.currentLocality(
                            at: archiveURL,
                            manifest: manifest
                        )
                    } catch {
                        if needsLegacySupplement {
                            try markLegacyProjectionReview(&record)
                        }
                        throw LocalVaultRestoreError.fromLocalityFailure(error)
                    }
                    guard postPrepareLocality == .fullyLocalCurrent else {
                        if needsLegacySupplement {
                            try markLegacyProjectionReview(&record)
                        }
                        throw LocalVaultRestoreError.archiveLocalityUnavailable
                    }
                    if requiresArchiveTransferBinding {
                        try requireArchiveTransferBinding(&record)
                    }
                    try validateArchiveGeneration(record.archiveGenerationURL)
                    if needsLegacySupplement, record.projectionSupplement == nil {
                        guard let projectionStore,
                              let archiveTransferID = record.archiveTransferID,
                              let archiveTransferState = record.archiveTransferState else {
                            try markLegacyProjectionReview(&record)
                            throw LocalVaultRestoreError.archiveLocalityUnavailable
                        }
                        let supplement: VaultProjectionSupplement
                        do {
                            supplement = try VaultProjectionSupplementBuilder(
                                fileManager: fileManager
                            ).build(at: record.archiveGenerationURL, verifiedAgainst: manifest)
                        } catch VaultProjectionSupplementError.identityMismatch {
                            try markLegacyProjectionIdentityMismatchReview(&record)
                            throw LocalVaultRestoreError.legacyProjectionIdentityMismatch
                        }
                        _ = try projectionStore.compareAndSetProjectionSupplement(
                            supplement,
                            transferID: archiveTransferID,
                            expectedManifest: manifest,
                            expectedDestinationURL: record.archiveGenerationURL,
                            expectedState: archiveTransferState
                        )
                        record.projectionSupplement = supplement
                        try persist(&record)
                    }
                    if let supplement = record.projectionSupplement {
                        try supplement.validate(against: manifest)
                    }
                    try manifestBuilder.verifyArchive(manifest, at: record.archiveGenerationURL)
                    if record.failureReason != nil || record.error != nil {
                        record.failureReason = nil
                        record.error = nil
                        try persist(&record)
                    }
                    try advance(&record, to: .copyingToActiveStaging)
                case .copyingToActiveStaging:
                    try inject(.copyingToActiveStaging, record)
                    if !fileManager.fileExists(atPath: record.stagingURL.path) {
                        let locality: ArchiveStorageLocality
                        do {
                            locality = try await provider.currentLocality(
                                at: record.archiveGenerationURL,
                                manifest: record.manifest
                            )
                        } catch {
                            throw LocalVaultRestoreError.fromLocalityFailure(error)
                        }
                        guard locality == .fullyLocalCurrent else {
                            if Self.requiresProjectionSupplement(record.manifest),
                               record.projectionSupplement == nil {
                                try markLegacyProjectionReview(&record)
                                throw LocalVaultRestoreError.archiveLocalityUnavailable
                            }
                            record.phase = .materializingArchive
                            try persist(&record)
                            continue
                        }
                    }
                    try await copyToStaging(
                        &record,
                        requiresArchiveTransferBinding: requiresArchiveTransferBinding
                    )
                    try advance(&record, to: .verifyingActiveStaging)
                case .verifyingActiveStaging:
                    try inject(.verifyingActiveStaging, record)
                    try manifestBuilder.verify(record.manifest, at: record.stagingURL)
                    try advance(&record, to: .promotingActiveCopy)
                case .promotingActiveCopy:
                    try inject(.promotingActiveCopy, record)
                    try promote(record)
                    try advance(&record, to: .persistingActiveLocation)
                case .persistingActiveLocation:
                    try inject(.persistingActiveLocation, record)
                    try revalidatePromotedActiveDestination(&record)
                    if !record.catalogLocationPersisted {
                        let relative = String(record.destinationURL.path.dropFirst(activeRoot.path.count + 1))
                        try catalog.persistActiveLocation(
                            projectID: record.projectID,
                            location: ProjectLocation(rootID: activeRootID, relativePath: relative, kind: .active, availability: .local, lastSeenAt: now())
                        )
                        record.catalogLocationPersisted = true
                        try persist(&record)
                    }
                    try advance(&record, to: .openingInCubase)
                case .openingInCubase:
                    try inject(.openingInCubase, record)
                    try revalidatePromotedActiveDestination(&record)
                    _ = try projectOpener.openProject(at: record.destinationURL, allowedRoot: activeRoot)
                    record.completedAt = now()
                    record.error = nil
                    try persist(&record)
                case .superseded:
                    throw LocalVaultRestoreError.archiveGenerationNotFound
                }
            }
            return record
        } catch is VaultTransferInterruption {
            throw VaultTransferInterruption()
        } catch {
            let reportedError: Error
            switch error {
            case FileProviderArchiveStorageError.expectedFileSizeMismatch,
                 FileProviderArchiveStorageError.expectedItemMismatch:
                reportedError = LocalVaultRestoreError.fromLocalityFailure(error)
            default:
                reportedError = error
            }
            if case LocalVaultRestoreError.archiveContentsChanged = reportedError {
                record.failureReason = .archiveGenerationIntegrityMismatch
                record.error = reportedError.localizedDescription
            } else {
                record.error = String(describing: reportedError)
            }
            try persist(&record)
            throw reportedError
        }
    }

    private func copyToStaging(
        _ record: inout VaultRestoreRecord,
        requiresArchiveTransferBinding: Bool
    ) async throws {
        try validate(record)
        if fileManager.fileExists(atPath: record.stagingURL.path) {
            do {
                try manifestBuilder.verify(record.manifest, at: record.stagingURL)
                return
            } catch {
                // A process can die after creating only part of the staging tree.
                // Preserve those bytes as recovery evidence, bind this same restore
                // to a fresh managed sibling, and persist that identity before any
                // new copy begins. A second crash therefore rotates again without
                // deleting or overwriting any earlier partial tree.
                if requiresArchiveTransferBinding {
                    try requireArchiveTransferBinding(&record)
                }
                let freshStagingURL = record.stagingURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        "\(record.id.uuidString.lowercased())-recovery-\(UUID().uuidString.lowercased())",
                        isDirectory: true
                    )
                guard !fileManager.fileExists(atPath: freshStagingURL.path) else {
                    throw LocalVaultRestoreError.unsafeStagingPath
                }
                record.stagingURL = freshStagingURL
                try validate(record)
                try persist(&record)
            }
        }
        let sourceURL = record.archiveGenerationURL
        let stagingURL = record.stagingURL
        let activeRoot = self.activeRoot
        let archiveRoot = self.archiveRoot
        let manifest = record.manifest
        let manifestBuilder = self.manifestBuilder
        let provider = self.provider
        let recordForValidation = record
        let fileManager = VaultRestoreSendableFileManager(self.fileManager)
        let volumeIdentifier = self.volumeIdentifier
        if requiresArchiveTransferBinding {
            try requireArchiveTransferBinding(&record)
        }
        try await writeAdmission(VaultWriteAdmissionRequest(
            target: .active,
            sourceURL: sourceURL,
            targetRootURL: activeRoot,
            minimumProjectedBytes: manifest.totalBytes,
            manifest: nil,
            projection: .liveSource(sourceURL)
        )) {
            try Self.validate(recordForValidation, activeRoot: activeRoot)
            try Self.validateArchiveGeneration(
                sourceURL,
                archiveRoot: archiveRoot,
                fileManager: fileManager.value
            )
            let locality: ArchiveStorageLocality
            do {
                locality = try await provider.currentLocality(at: sourceURL, manifest: manifest)
            } catch {
                throw LocalVaultRestoreError.fromLocalityFailure(error)
            }
            guard locality == .fullyLocalCurrent else {
                throw LocalVaultRestoreError.archiveLocalityUnavailable
            }
            try Self.validateArchiveGeneration(
                sourceURL,
                archiveRoot: archiveRoot,
                fileManager: fileManager.value
            )
            guard try volumeIdentifier(stagingURL.deletingLastPathComponent())
                    == volumeIdentifier(activeRoot) else {
                throw LocalVaultRestoreError.writeTargetVolumeMismatch
            }
            try fileManager.value.createDirectory(at: stagingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try VaultManifestCopier.copy(
                manifest,
                from: sourceURL,
                to: stagingURL,
                fileManager: fileManager.value
            )

            // Detect any source mutation that raced the admitted exact-entry copy.
            // Verify retained staging even when source postflight fails, so recovery
            // never inherits an unverified or out-of-manifest byte tree.
            let sourcePostflightError: Error?
            do {
                try manifestBuilder.verifyArchive(manifest, at: sourceURL)
                sourcePostflightError = nil
            } catch {
                sourcePostflightError = error
            }
            try manifestBuilder.verify(manifest, at: stagingURL)
            if let sourcePostflightError { throw sourcePostflightError }
        }
    }

    private func promote(_ record: VaultRestoreRecord) throws {
        try validate(record)
        let destinationExists = fileManager.fileExists(atPath: record.destinationURL.path)
        let stagingExists = fileManager.fileExists(atPath: record.stagingURL.path)
        if destinationExists {
            guard !stagingExists else { throw LocalVaultRestoreError.occupiedDestination }
            try manifestBuilder.verify(record.manifest, at: record.destinationURL)
            return
        }
        guard stagingExists else { throw VaultManifestError.missingRoot }
        let destinationParent = record.destinationURL.deletingLastPathComponent()
        let stagingVolume = try volumeIdentifier(record.stagingURL)
        let destinationVolume = try volumeIdentifier(destinationParent)
        guard stagingVolume == destinationVolume else {
            throw LocalVaultRestoreError.crossVolumePromotion
        }
        // Volume lookup can await platform state or traverse a mounted parent.
        // Recheck canonical containment at the final rename boundary.
        try validate(record)
        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        try fileManager.moveItem(at: record.stagingURL, to: record.destinationURL)
        try manifestBuilder.verify(record.manifest, at: record.destinationURL)
    }

    private func revalidatePromotedActiveDestination(
        _ record: inout VaultRestoreRecord
    ) throws {
        do {
            // A crash/relaunch or sync mutation can change the promoted Active
            // tree after its earlier verification. Recheck containment and exact
            // manifest identity at the final synchronous Catalog/Open boundary.
            try validate(record)
            try manifestBuilder.verify(record.manifest, at: record.destinationURL)
        } catch {
            record.failureReason = .activeDestinationIntegrityMismatch
            record.error = "Promoted Active destination changed before Catalog/Open: \(error)"
            try persist(&record)
            throw LocalVaultRestoreError.activeDestinationIntegrityMismatch
        }
    }

    private func validate(_ record: VaultRestoreRecord) throws {
        try Self.validate(record, activeRoot: activeRoot)
    }

    private static func validate(_ record: VaultRestoreRecord, activeRoot: URL) throws {
        let stagingRoot = activeRoot.appendingPathComponent(".niko-staging", isDirectory: true)
        let safety = PathSafety()
        guard safety.isResolvedContainedWithoutNestedSymlinks(stagingRoot, in: activeRoot),
              stagingRoot != activeRoot else {
            throw LocalVaultRestoreError.unsafeStagingPath
        }
        guard safety.isResolvedContainedWithoutNestedSymlinks(record.stagingURL, in: stagingRoot),
              record.stagingURL != stagingRoot else { throw LocalVaultRestoreError.unsafeStagingPath }
        guard safety.isResolvedContainedWithoutNestedSymlinks(record.destinationURL, in: activeRoot),
              record.destinationURL != activeRoot,
              !safety.isResolvedContained(record.destinationURL, in: [stagingRoot]) else {
            throw LocalVaultRestoreError.invalidDestination
        }
    }

    private func validateArchiveGeneration(_ generationURL: URL) throws {
        try Self.validateArchiveGeneration(
            generationURL,
            archiveRoot: archiveRoot,
            fileManager: fileManager
        )
    }

    private static func validateArchiveGeneration(
        _ generationURL: URL,
        archiveRoot: URL?,
        fileManager: FileManager
    ) throws {
        guard let archiveRoot else { throw LocalVaultRestoreError.unsafeArchiveGenerationPath }
        let generationsRoot = archiveRoot.appendingPathComponent("generations", isDirectory: true)
        let safety = PathSafety(fileManager: fileManager)
        guard safety.isResolvedContainedWithoutNestedSymlinks(generationsRoot, in: archiveRoot),
              safety.isResolvedContainedWithoutNestedSymlinks(generationURL, in: generationsRoot),
              generationURL != generationsRoot else {
            throw LocalVaultRestoreError.unsafeArchiveGenerationPath
        }
    }

    private func destinationURL(relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw LocalVaultRestoreError.invalidDestination
        }
        let destination = activeRoot.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        guard Self.contains(activeRoot, destination), destination != activeRoot,
              !Self.contains(activeRoot.appendingPathComponent(".niko-staging", isDirectory: true), destination) else {
            throw LocalVaultRestoreError.invalidDestination
        }
        return destination
    }

    private static func requiresProjectionSupplement(_ manifest: VaultManifest) -> Bool {
        manifest.rootAllocatedByteCount == nil
            || manifest.rootExtendedAttributeBytes == nil
            || manifest.entries.contains {
                $0.allocatedByteCount == nil || $0.extendedAttributeBytes == nil
            }
    }

    private func markLegacyProjectionReview(_ record: inout VaultRestoreRecord) throws {
        record.failureReason = .legacyProjectionEvidenceUnavailable
        try persist(&record)
    }

    private func markLegacyProjectionIdentityMismatchReview(
        _ record: inout VaultRestoreRecord
    ) throws {
        record.failureReason = .legacyProjectionIdentityMismatch
        try persist(&record)
    }

    private func requireArchiveTransferBinding(_ record: inout VaultRestoreRecord) throws {
        let verifiedTerminalStates: Set<VaultTransferState> = [
            .archiveVerified, .archivedLocal, .archivedOnlineOnly,
        ]
        do {
            guard let projectionStore,
                  let archiveTransferID = record.archiveTransferID,
                  let recordedState = record.archiveTransferState,
                  verifiedTerminalStates.contains(recordedState),
                  let archiveTransfer = try projectionStore.record(id: archiveTransferID),
                  archiveTransfer.id == archiveTransferID,
                  archiveTransfer.projectID == record.projectID,
                  verifiedTerminalStates.contains(archiveTransfer.state),
                  Self.canonicalPath(archiveTransfer.destinationURL)
                    == Self.canonicalPath(record.archiveGenerationURL),
                  archiveTransfer.manifestID == record.manifest.id,
                  let archiveManifest = archiveTransfer.manifest,
                  archiveManifest.id == record.manifest.id,
                  archiveManifest.archiveLayout == record.manifest.archiveLayout,
                  archiveManifest.hasSameImmutableContent(as: record.manifest) else {
                throw LocalVaultRestoreError.archiveTransferBindingUnavailable
            }

            switch (record.projectionSupplement, archiveTransfer.projectionSupplement) {
            case (nil, nil):
                break
            case (nil, let authoritativeSupplement?):
                try authoritativeSupplement.validate(against: record.manifest)
                try authoritativeSupplement.validate(against: archiveManifest)
                record.projectionSupplement = authoritativeSupplement
                try persist(&record)
            case (let supplement?, let authoritativeSupplement?) where supplement == authoritativeSupplement:
                try supplement.validate(against: record.manifest)
                try supplement.validate(against: archiveManifest)
            default:
                throw LocalVaultRestoreError.archiveTransferBindingUnavailable
            }
        } catch {
            record.failureReason = .archiveTransferBindingUnavailable
            try persist(&record)
            throw LocalVaultRestoreError.archiveTransferBindingUnavailable
        }
    }

    private func advance(_ record: inout VaultRestoreRecord, to phase: VaultRestorePhase) throws {
        record.phase = phase
        try persist(&record)
    }

    private func persist(_ record: inout VaultRestoreRecord) throws {
        record.updatedAt = now()
        try store.saveRestore(record)
    }

    private func inject(_ point: VaultRestoreFaultPoint, _ record: VaultRestoreRecord) throws {
        try faultInjector?(point, record)
    }

    private static func contains(_ root: URL, _ candidate: URL) -> Bool {
        PathSafety().isResolvedContained(candidate, in: [root])
    }

    private static func canonicalPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
        for alias in ["/private/var", "/private/tmp"] {
            if path == alias { return String(alias.dropFirst("/private".count)) }
            if path.hasPrefix(alias + "/") { return String(path.dropFirst("/private".count)) }
        }
        return path
    }
}

private struct VaultRestoreSendableFileManager: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}
