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

    /// Capture API usable before confirmation (no lease, no transfer). Binds
    /// source path + filesystem object, song/catalog identity where known,
    /// current root IDs + paths + filesystem objects, trigger, and the
    /// destructiveness ceiling. Stable live gates are checked now for removal
    /// requests so the UI can fall back to a copy-only capture; a copy-only
    /// capture (`removingActiveCopy: false`) is always permitted, even when
    /// live gates would forbid removal. Volatile activity probes run at
    /// execution. Never binds titles, never mutates settings.
    public func captureArchiveAuthorization(
        for song: Song,
        trigger: ProjectVaultArchiveTrigger,
        removingActiveCopy: Bool,
        catalogProjectID: ProjectID?
    ) async throws -> ProjectVaultArchiveAuthorization {
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        guard settings.vault.isEnabled else { throw ProjectVaultRuntimeError.disabled }
        if trigger == .backupCopy, removingActiveCopy {
            throw ProjectVaultAuthorizationError.backupCopyRemovalForbidden
        }
        let maximum: ProjectVaultArchiveDestructiveness = removingActiveCopy ? .mayRemoveActiveCopy : .copyOnly
        let canonicalSource = ProjectVaultArchiveAuthorization.canonicalPath(for: song.folderPath)
        guard FileManager.default.fileExists(atPath: song.folderPath.path) else {
            throw ProjectVaultRuntimeError.sourceUnavailable(title: song.effectiveDisplayTitle)
        }
        let identity: ProjectVaultSourceFileSystemIdentity
        do {
            identity = try ProjectVaultArchiveAuthorization.fileSystemIdentity(at: song.folderPath)
        } catch {
            throw ProjectVaultRuntimeError.sourceUnavailable(title: song.effectiveDisplayTitle)
        }
        if removingActiveCopy {
            guard !settings.vault.automationEmergencyStop else { throw ProjectVaultRuntimeError.emergencyStop }
            if trigger == .manual {
                guard settings.vault.independentBackupConfirmed else {
                    throw ProjectVaultRuntimeError.independentBackupRequired
                }
            } else {
                try validateAutomaticArchivingEligibility(settings: settings, song: song)
                guard ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(settings.vault) else {
                    throw ProjectVaultRuntimeError.automaticArchivingDisabled
                }
            }
            var keys = Set([
                song.id,
                canonicalSource,
                song.folderPath.standardizedFileURL.path,
                song.folderPath.standardizedFileURL.resolvingSymlinksInPath().path,
            ])
            if let known = catalogProjectID {
                keys.insert(known.description)
            }
            guard settings.vault.keepLocalProjectIDs.isDisjoint(with: keys) else {
                throw ProjectVaultRuntimeError.keepLocal
            }
        }
        let activeRootIdentity: ProjectVaultSourceFileSystemIdentity
        do {
            activeRootIdentity = try ProjectVaultArchiveAuthorization.fileSystemIdentity(at: configuration.active.url)
        } catch {
            throw ProjectVaultRuntimeError.rootUnavailable(.active)
        }
        let archiveRootIdentity: ProjectVaultSourceFileSystemIdentity
        do {
            archiveRootIdentity = try ProjectVaultArchiveAuthorization.fileSystemIdentity(at: configuration.archive.url)
        } catch {
            throw ProjectVaultRuntimeError.rootUnavailable(.archive)
        }
        return ProjectVaultArchiveAuthorization(
            sourceCanonicalPath: canonicalSource,
            sourceFileSystemIdentity: identity,
            songID: song.id,
            catalogProjectID: catalogProjectID,
            activeRootID: configuration.active.id,
            activeRootCanonicalPath: ProjectVaultArchiveAuthorization.canonicalPath(for: configuration.active.url),
            activeRootFileSystemIdentity: activeRootIdentity,
            archiveRootID: configuration.archive.id,
            archiveRootCanonicalPath: ProjectVaultArchiveAuthorization.canonicalPath(for: configuration.archive.url),
            archiveRootFileSystemIdentity: archiveRootIdentity,
            trigger: trigger,
            maximumDestructiveness: maximum,
            authorizedAt: now()
        )
    }

    public func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot {
        let lease = try acquireMutationLease()
        defer { releaseMutationLease(lease) }
        return try await performArchive(song: song, trigger: trigger, authorization: nil)
    }

    public func archive(
        song: Song,
        trigger: ProjectVaultArchiveTrigger,
        authorization: ProjectVaultArchiveAuthorization
    ) async throws -> ProjectVaultRuntimeSnapshot {
        let lease = try acquireMutationLease()
        defer { releaseMutationLease(lease) }
        return try await performArchive(song: song, trigger: trigger, authorization: authorization)
    }

    private func performArchive(
        song: Song,
        trigger: ProjectVaultArchiveTrigger,
        authorization: ProjectVaultArchiveAuthorization?
    ) async throws -> ProjectVaultRuntimeSnapshot {
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        guard settings.vault.isEnabled else { throw ProjectVaultRuntimeError.disabled }
        if trigger == .workflowDone {
            try validateAutomaticArchivingEligibility(settings: settings, song: song)
        }
        let executionStart = now()
        if let authorization {
            try validateConfirmationAuthorization(
                authorization,
                for: song,
                trigger: trigger,
                configuration: configuration,
                executionStart: executionStart
            )
            if trigger == .backupCopy, authorization.permitsRemoval {
                throw ProjectVaultAuthorizationError.backupCopyRemovalForbidden
            }
            let liveIdentity: ProjectVaultSourceFileSystemIdentity
            do {
                liveIdentity = try ProjectVaultArchiveAuthorization.fileSystemIdentity(at: song.folderPath)
            } catch {
                if !FileManager.default.fileExists(atPath: song.folderPath.path) {
                    throw ProjectVaultRuntimeError.sourceUnavailable(title: song.effectiveDisplayTitle)
                }
                throw ProjectVaultAuthorizationError.sourceIdentityMismatch
            }
            guard liveIdentity == authorization.sourceFileSystemIdentity else {
                throw ProjectVaultAuthorizationError.sourceIdentityMismatch
            }
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
            try validateCatalogBinding(authorization, entry: entry)
            return try await reuseVerifiedTerminal(
                persistedSourceTransfer,
                entry: entry,
                context: context,
                authorization: authorization
            )
        }
        let entry = try ensureCatalogEntry(for: song, configuration: configuration)
        try validateCatalogBinding(authorization, entry: entry)
        let latest = try persistedSourceTransfer ?? latestTransfer(projectID: entry.record.id)
        if let latest {
            if VaultTransferOwnershipPolicy.isVerifiedTerminal(latest.state),
               try reuseCheck.matchesCurrentSource(latest),
               await reuseCheck.hasUsableArchiveGeneration(latest) {
                return try await reuseVerifiedTerminal(
                    latest,
                    entry: entry,
                    context: context,
                    authorization: authorization
                )
            }
            if VaultTransferOwnershipPolicy.ownsProject(latest.state) {
                throw ProjectVaultRuntimeError.transferOwned
            }
        }
        let writeAdmission: LocalVaultTransferEngine.WriteAdmission
        if let authorization {
            // The entry validation above precedes the provider/terminal-reuse
            // awaits, so the copy mutations are additionally bound to the
            // confirmation inside the admission, which rechecks live identity
            // and restrictions after its awaits, immediately before each
            // enclosed mutation.
            writeAdmission = makeBoundWriteAdmission(
                authorization: authorization,
                song: song,
                trigger: trigger,
                settings: settings
            )
        } else {
            writeAdmission = makeWriteAdmission(settings: settings)
        }
        let removalAdmission: LocalVaultTransferEngine.RemovalAdmission
        if let authorization {
            removalAdmission = makeBoundRemovalAdmission(
                authorization: authorization,
                song: song,
                trigger: trigger
            )
        } else {
            removalAdmission = makeCopyOnlyRemovalAdmission()
        }
        let engine = try LocalVaultTransferEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            store: transferStore,
            provider: context.provider,
            now: now,
            recoveryPolicy: recoveryPolicy,
            writeAdmission: writeAdmission,
            removalAdmission: removalAdmission
        )
        let transfer: VaultTransferRecord
        if trigger == .workflowDone {
            transfer = try await runAutomaticArchive(
                entry: entry,
                engine: engine,
                context: context,
                authorization: authorization
            )
        } else {
            transfer = try await engine.archive(projectID: entry.record.id, sourceURL: song.folderPath)
        }
        try settingsStore.updateSettings { $0.vault.lastSuccessfulVerificationAt = now() }
        let updatedEntry = try catalogStore.loadEntries().first { $0.record.id == entry.record.id } ?? entry
        if trigger == .manual {
            // Compatibility (nil) and copy-only authorizations stay copy-only
            // inside `reuseVerifiedTerminal`; only a bound removal
            // authorization deletes. `.workflowDone` returns the scheduler
            // result directly: the scheduler already attempted bound removal
            // when authorized, and the compatibility path is copy-only by
            // construction (see the Done contract in
            // `ProjectVaultArchiveAuthorization.swift`).
            return try await reuseVerifiedTerminal(
                transfer,
                entry: updatedEntry,
                context: context,
                authorization: authorization
            )
        }
        return snapshot(entry: updatedEntry, transfer: transfer, configuration: configuration)
    }

    private func validateConfirmationAuthorization(
        _ authorization: ProjectVaultArchiveAuthorization,
        for song: Song,
        trigger: ProjectVaultArchiveTrigger,
        configuration: Configuration,
        executionStart: Date
    ) throws {
        guard authorization.trigger == trigger else {
            throw ProjectVaultAuthorizationError.triggerMismatch
        }
        guard authorization.songID == song.id else {
            throw ProjectVaultAuthorizationError.songMismatch
        }
        guard authorization.sourceCanonicalPath == ProjectVaultArchiveAuthorization.canonicalPath(for: song.folderPath) else {
            throw ProjectVaultAuthorizationError.sourcePathMismatch
        }
        guard authorization.activeRootID == configuration.active.id,
              authorization.activeRootCanonicalPath == ProjectVaultArchiveAuthorization.canonicalPath(for: configuration.active.url),
              authorization.archiveRootID == configuration.archive.id,
              authorization.archiveRootCanonicalPath == ProjectVaultArchiveAuthorization.canonicalPath(for: configuration.archive.url) else {
            throw ProjectVaultAuthorizationError.rootMismatch
        }
        let liveActiveRootIdentity = try? ProjectVaultArchiveAuthorization.fileSystemIdentity(at: configuration.active.url)
        let liveArchiveRootIdentity = try? ProjectVaultArchiveAuthorization.fileSystemIdentity(at: configuration.archive.url)
        guard liveActiveRootIdentity == authorization.activeRootFileSystemIdentity,
              liveArchiveRootIdentity == authorization.archiveRootFileSystemIdentity else {
            throw ProjectVaultAuthorizationError.rootMismatch
        }
        guard authorization.authorizedAt <= executionStart else {
            throw ProjectVaultAuthorizationError.authorizationRequired
        }
    }

    private func validateCatalogBinding(
        _ authorization: ProjectVaultArchiveAuthorization?,
        entry: ProjectCatalogEntry
    ) throws {
        guard let expected = authorization?.catalogProjectID else { return }
        guard entry.record.id == expected else {
            throw ProjectVaultAuthorizationError.catalogMismatch
        }
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

    /// Finishes a verified terminal transfer by removing the Active copy only
    /// when a bound authorization permits it; otherwise reports the transfer
    /// as it stands. The compatibility (nil authorization) path is always
    /// copy-only, and a copy-only authorization never escalates via live
    /// settings. Live restriction, root/source revalidation, and the final
    /// activity probe all happen inside the bound admission, which rechecks
    /// after its final await immediately before removal.
    private func reuseVerifiedTerminal(
        _ transfer: VaultTransferRecord,
        entry: ProjectCatalogEntry,
        context: ArchiveContext,
        authorization: ProjectVaultArchiveAuthorization?
    ) async throws -> ProjectVaultRuntimeSnapshot {
        let trigger = context.trigger
        let configuration = context.configuration
        guard let authorization,
              authorization.permitsRemoval,
              trigger != .backupCopy,
              authorization.trigger == trigger,
              VaultTransferOwnershipPolicy.isVerifiedTerminal(transfer.state),
              FileManager.default.fileExists(atPath: transfer.sourceURL.path) else {
            return snapshot(entry: entry, transfer: transfer, configuration: configuration)
        }

        let removalAdmission = makeBoundRemovalAdmission(
            authorization: authorization,
            song: context.song,
            trigger: trigger
        )
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
    /// inactivity, capacity, and activity policy gate the copy. The scheduler
    /// only attempts removal when a bound authorization permits it; otherwise
    /// it preserves the automatic copy. The bound admission still restricts
    /// via live settings and revalidates after its final await.
    private func runAutomaticArchive(
        entry: ProjectCatalogEntry,
        engine: LocalVaultTransferEngine,
        context: ArchiveContext,
        authorization: ProjectVaultArchiveAuthorization?
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
            removesActiveCopy: authorization?.permitsRemoval == true,
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
