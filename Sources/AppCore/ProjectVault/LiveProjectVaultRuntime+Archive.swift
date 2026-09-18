import Foundation
import NikoMusicCore

extension LiveProjectVaultRuntime {
    /// Inputs resolved once per `archive(song:trigger:)` call and shared by its steps.
    private struct ArchiveContext {
        let song: Song
        let trigger: ProjectVaultArchiveTrigger
        let settings: AppSettings
        let configuration: Configuration
        let provider: any ArchiveStorageProvider
    }

    /// A canonical source path is not a content identity: Restore/Edit can
    /// repopulate the same Active folder after an older terminal archive.
    /// Observes the current tree once and memoizes each terminal comparison so
    /// the two catalog lookup paths cannot hash a large project twice.
    private struct VerifiedTerminalReuseCheck {
        let sourceURL: URL
        let archiveRootURL: URL
        let sourceManifestBuilder: @Sendable (URL) throws -> VaultManifest
        let provider: any ArchiveStorageProvider
        private let archiveManifestBuilder = VaultManifestBuilder()
        private var observedSourceManifest: VaultManifest?
        private var terminalIdentityMatches: [UUID: Bool] = [:]
        private var terminalUsability: [UUID: Bool] = [:]

        init(
            sourceURL: URL,
            archiveRootURL: URL,
            sourceManifestBuilder: @escaping @Sendable (URL) throws -> VaultManifest,
            provider: any ArchiveStorageProvider
        ) {
            self.sourceURL = sourceURL
            self.archiveRootURL = archiveRootURL
            self.sourceManifestBuilder = sourceManifestBuilder
            self.provider = provider
        }

        mutating func matchesCurrentSource(_ transfer: VaultTransferRecord) throws -> Bool {
            if let cached = terminalIdentityMatches[transfer.id] { return cached }
            let canonicalSource = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
            let expectedGeneration = archiveRootURL
                .appendingPathComponent("generations", isDirectory: true)
                .appendingPathComponent(transfer.projectID.description, isDirectory: true)
                .appendingPathComponent("generation-\(transfer.id.uuidString.lowercased())", isDirectory: true)
            guard transfer.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path == canonicalSource.path,
                  transfer.destinationURL.standardizedFileURL.resolvingSymlinksInPath().path == expectedGeneration.standardizedFileURL.resolvingSymlinksInPath().path,
                  let expected = transfer.manifest,
                  transfer.manifestID == expected.id else {
                terminalIdentityMatches[transfer.id] = false
                return false
            }
            do {
                try expected.validatePersistedContentEnvelope()
            } catch {
                terminalIdentityMatches[transfer.id] = false
                return false
            }
            let observed: VaultManifest
            if let observedSourceManifest {
                observed = observedSourceManifest
            } else {
                observed = try sourceManifestBuilder(sourceURL)
                observedSourceManifest = observed
            }
            let matches = expected.hasSameImmutableContent(as: observed)
            terminalIdentityMatches[transfer.id] = matches
            return matches
        }

        mutating func hasUsableArchiveGeneration(_ transfer: VaultTransferRecord) async -> Bool {
            if let cached = terminalUsability[transfer.id] { return cached }
            let isUsable = await LiveProjectVaultRuntime.hasUsableArchiveGeneration(
                transfer,
                provider: provider,
                manifestBuilder: archiveManifestBuilder
            )
            terminalUsability[transfer.id] = isUsable
            return isUsable
        }
    }

    public func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot {
        let lease = try acquireMutationLease()
        defer { releaseMutationLease(lease) }
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        guard settings.vault.isEnabled else { throw ProjectVaultRuntimeError.disabled }
        if trigger == .workflowDone {
            try validateAutomaticArchivingEligibility(settings: settings, song: song)
        }

        let persistedSourceTransfer = try latestTransfer(sourceURL: song.folderPath)
        if let persistedSourceTransfer, VaultTransferOwnershipPolicy.ownsProject(persistedSourceTransfer.state) {
            throw ProjectVaultRuntimeError.transferOwned
        }

        let context = ArchiveContext(
            song: song,
            trigger: trigger,
            settings: settings,
            configuration: configuration,
            provider: archiveProvider(root: configuration.archive.url)
        )
        var reuseCheck = VerifiedTerminalReuseCheck(
            sourceURL: song.folderPath,
            archiveRootURL: configuration.archive.url,
            sourceManifestBuilder: sourceManifestBuilder,
            provider: context.provider
        )

        if let persistedSourceTransfer,
           VaultTransferOwnershipPolicy.isVerifiedTerminal(persistedSourceTransfer.state),
           try catalogStore.loadEntries().contains(where: {
               $0.record.id == persistedSourceTransfer.projectID
           }),
           try reuseCheck.matchesCurrentSource(persistedSourceTransfer),
           await reuseCheck.hasUsableArchiveGeneration(persistedSourceTransfer) {
            let entry = try ensureCatalogEntry(for: song, configuration: configuration)
            return try await reuseVerifiedTerminal(persistedSourceTransfer, entry: entry, context: context)
        }
        let entry = try ensureCatalogEntry(for: song, configuration: configuration)
        let latest = try persistedSourceTransfer ?? latestTransfer(projectID: entry.record.id)
        if let latest {
            if VaultTransferOwnershipPolicy.isVerifiedTerminal(latest.state),
               try reuseCheck.matchesCurrentSource(latest),
               await reuseCheck.hasUsableArchiveGeneration(latest) {
                return try await reuseVerifiedTerminal(latest, entry: entry, context: context)
            }
            if VaultTransferOwnershipPolicy.ownsProject(latest.state) {
                throw ProjectVaultRuntimeError.transferOwned
            }
        }
        let writeAdmission = makeWriteAdmission(settings: settings)
        let engine = try LocalVaultTransferEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            store: transferStore,
            provider: context.provider,
            now: now,
            recoveryPolicy: recoveryPolicy,
            writeAdmission: writeAdmission,
            removalAdmission: makeRemovalAdmission(song: song, trigger: trigger)
        )
        let transfer: VaultTransferRecord
        if trigger == .workflowDone {
            transfer = try await runAutomaticArchive(entry: entry, engine: engine, context: context)
        } else {
            transfer = try await engine.archive(projectID: entry.record.id, sourceURL: song.folderPath)
        }
        try settingsStore.updateSettings { $0.vault.lastSuccessfulVerificationAt = now() }
        let updatedEntry = try catalogStore.loadEntries().first { $0.record.id == entry.record.id } ?? entry
        if trigger == .manual {
            return try await reuseVerifiedTerminal(transfer, entry: updatedEntry, context: context)
        }
        return snapshot(entry: updatedEntry, transfer: transfer, configuration: configuration)
    }

    /// Workflow-done archiving is opt-in and must respect the rollout stage,
    /// Emergency Stop, and Keep Local before any transfer starts.
    private func validateAutomaticArchivingEligibility(settings: AppSettings, song: Song) throws {
        guard settings.vault.automaticArchiving else { throw ProjectVaultRuntimeError.automaticArchivingDisabled }
        guard !settings.vault.automationEmergencyStop else { throw ProjectVaultRuntimeError.emergencyStop }
        guard settings.vault.rolloutStage != .disabled else { throw ProjectVaultRuntimeError.automaticArchivingDisabled }
        let keepLocalKeys = Set([
            song.id,
            song.folderPath.standardizedFileURL.path,
            song.folderPath.standardizedFileURL.resolvingSymlinksInPath().path,
        ])
        guard settings.vault.keepLocalProjectIDs.isDisjoint(with: keepLocalKeys) else {
            throw ProjectVaultRuntimeError.keepLocal
        }
    }

    /// Finishes a verified terminal transfer by removing the Active copy when the
    /// trigger permits it; otherwise reports the transfer as it stands.
    private func reuseVerifiedTerminal(
        _ transfer: VaultTransferRecord,
        entry: ProjectCatalogEntry,
        context: ArchiveContext
    ) async throws -> ProjectVaultRuntimeSnapshot {
        let trigger = context.trigger
        let configuration = context.configuration
        guard trigger == .manual || (trigger == .workflowDone && ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(context.settings.vault)),
              VaultTransferOwnershipPolicy.isVerifiedTerminal(transfer.state),
              FileManager.default.fileExists(atPath: transfer.sourceURL.path) else {
            return snapshot(entry: entry, transfer: transfer, configuration: configuration)
        }

        let removalAdmission = makeRemovalAdmission(song: context.song, trigger: trigger)
        do {
            try await removalAdmission(transfer)
        } catch let error as ProjectVaultRuntimeError {
            if case .activityPostponed = error, trigger == .workflowDone {
                return snapshot(entry: entry, transfer: transfer, configuration: configuration)
            }
            throw error
        }
        let engine = try LocalVaultTransferEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            store: transferStore,
            provider: context.provider,
            now: now,
            recoveryPolicy: recoveryPolicy,
            removalAdmission: removalAdmission
        )
        let completed = try await engine.removeActiveCopy(after: transfer)
        try settingsStore.updateSettings { $0.vault.lastSuccessfulVerificationAt = now() }
        return snapshot(entry: entry, transfer: completed, configuration: configuration)
    }

    /// Runs a workflow-done archive through the automation scheduler so the
    /// inactivity, capacity, and activity policy gate the copy.
    private func runAutomaticArchive(
        entry: ProjectCatalogEntry,
        engine: LocalVaultTransferEngine,
        context: ArchiveContext
    ) async throws -> VaultTransferRecord {
        let song = context.song
        let settings = context.settings
        let previousVerifiedTransferID = try transferStore
            .verifiedArchiveGeneration(projectID: entry.record.id)?.id
        let policy = VaultAutomationPolicy(
            isVaultEnabled: settings.vault.isEnabled,
            isAutomaticArchivingEnabled: settings.vault.automaticArchiving,
            inactivityDays: settings.vault.inactivityDays,
            minimumFreeSpaceGiB: settings.vault.minimumFreeSpaceGiB,
            transferFreeSpaceReserveGiB: settings.vault.transferFreeSpaceReserveGiB
        )
        let capacity = try? capacityProbe.snapshot(
            sourceURL: song.folderPath,
            archiveRootURL: context.configuration.archive.url
        )
        let scheduler = VaultAutomationScheduler(
            policy: policy,
            activityProbe: activityProbe,
            archiver: engine,
            removesActiveCopy: ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(settings.vault),
            now: now
        )
        let candidate = VaultAutomationCandidate(
            projectID: entry.record.id,
            sourceURL: song.folderPath,
            isKeepLocal: false,
            lastActivityAt: song.effectiveLatestCPR?.modifiedAt,
            availableCapacityBytes: capacity?.activeAvailableCapacityBytes,
            archiveAvailableCapacityBytes: capacity?.archiveAvailableCapacityBytes,
            projectedArchiveBytes: capacity?.projectedArchiveBytes,
            trigger: .workflowDone
        )
        guard let result = await scheduler.run(candidates: [candidate]).first else {
            throw ProjectVaultRuntimeError.unavailable
        }
        switch result {
        case .archived(_, let record): return record
        case .postponed(_, let reason):
            guard let verified = try transferStore.verifiedArchiveGeneration(projectID: entry.record.id),
                  verified.id != previousVerifiedTransferID else {
                throw ProjectVaultRuntimeError.activityPostponed(reason)
            }
            // The copy and provider verification completed, but a volatile
            // safety probe blocked Active-copy removal. Surface the verified
            // generation as success so the UI does not schedule another full
            // Dropbox copy; the Active project remains untouched.
            return verified
        case .failed(let failure): throw ProjectVaultRuntimeError.archiveFailed(failure.message)
        }
    }

    private static func hasUsableArchiveGeneration(
        _ transfer: VaultTransferRecord,
        provider: any ArchiveStorageProvider,
        manifestBuilder: VaultManifestBuilder
    ) async -> Bool {
        guard VaultTransferOwnershipPolicy.isVerifiedTerminal(transfer.state),
              let manifestID = transfer.manifestID,
              let manifest = transfer.manifest,
              manifest.id == manifestID,
              (try? manifest.validatePersistedContentEnvelope()) != nil else {
            return false
        }

        switch transfer.state {
        case .archiveVerified, .archivedLocal:
            do {
                try manifestBuilder.verifyArchive(manifest, at: transfer.destinationURL)
                return true
            } catch {
                return false
            }
        case .archivedOnlineOnly:
            guard transfer.durability == .syncedToProvider
                    || transfer.durability == .independentlyBackedUp else {
                return false
            }
            do {
                switch try await provider.currentLocality(
                    at: transfer.destinationURL,
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
        default:
            return false
        }
    }
}
