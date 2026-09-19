import Foundation
import NikoMusicCore

extension LiveProjectVaultRuntime {
    func makeWriteAdmission(settings _: AppSettings) -> LocalVaultTransferEngine.WriteAdmission {
        let capacityProbe = self.capacityProbe
        let settingsStore = self.settingsStore
        return { request, operation in
            let budget = try Self.resolveWriteAdmissionBudget(
                request: request,
                capacityProbe: capacityProbe,
                settingsStore: settingsStore
            )
            if let reason = VaultArchiveWriteAdmissionEvaluator().postponement(
                availableCapacityBytes: budget.availableCapacityBytes,
                projectedCopyBytes: budget.projectedCopyBytes,
                minimumFreeSpaceGiB: budget.settings.vault.transferFreeSpaceReserveGiB
            ) {
                throw VaultWriteAdmissionError.postponed(reason)
            }
            try await operation()
        }
    }

    /// Bound write admission for an authorized archive copy. The entry check in
    /// `performArchive` runs before the provider/terminal-reuse awaits, so this
    /// admission binds the same confirmation (trigger, `Song.id`, source path +
    /// filesystem object, root IDs + paths + filesystem objects, catalog
    /// `ProjectID` where known, `authorizedAt` ordering) and rechecks it after
    /// the projection/capacity/policy awaits, immediately before the enclosed
    /// mutation. A root/source replacement during an awaited provider check
    /// therefore cannot copy into a changed target or execute under a stale
    /// approval. Copy-only authorizations stay copy-only here: this admission
    /// admits writes only and never authorizes removal, however permissive
    /// live settings become. Recovery/restore flows keep the unbound admission
    /// above; their call signatures are unchanged.
    func makeBoundWriteAdmission(
        authorization: ProjectVaultArchiveAuthorization,
        song: Song,
        trigger: ProjectVaultArchiveTrigger,
        settings _: AppSettings
    ) -> LocalVaultTransferEngine.WriteAdmission {
        let capacityProbe = self.capacityProbe
        let settingsStore = self.settingsStore
        let catalogStore = self.catalogStore
        let now = self.now
        return { request, operation in
            try Self.validateBoundCopyIdentity(
                authorization: authorization,
                song: song,
                trigger: trigger,
                request: request,
                settingsStore: settingsStore,
                catalogStore: catalogStore,
                now: now()
            )
            let budget = try Self.resolveWriteAdmissionBudget(
                request: request,
                capacityProbe: capacityProbe,
                settingsStore: settingsStore
            )
            if let reason = VaultArchiveWriteAdmissionEvaluator().postponement(
                availableCapacityBytes: budget.availableCapacityBytes,
                projectedCopyBytes: budget.projectedCopyBytes,
                minimumFreeSpaceGiB: budget.settings.vault.transferFreeSpaceReserveGiB
            ) {
                throw VaultWriteAdmissionError.postponed(reason)
            }
            // Recheck after the final await boundary, immediately before the
            // enclosed mutation: live settings, roots, source identity, and
            // the full confirmation binding.
            try Self.validateBoundCopyIdentity(
                authorization: authorization,
                song: song,
                trigger: trigger,
                request: request,
                settingsStore: settingsStore,
                catalogStore: catalogStore,
                now: now()
            )
            try await operation()
        }
    }

    /// Shared projection/capacity/policy snapshot for write admissions.
    /// Projection runs first (it can be long), capacity is sampled after it so
    /// it is the last filesystem snapshot before policy, and the user floor is
    /// reloaded last so stale policy never authorizes the enclosed mutation.
    static func resolveWriteAdmissionBudget(
        request: VaultWriteAdmissionRequest,
        capacityProbe: any ProjectVaultCapacityProbing,
        settingsStore: any SettingsStore
    ) throws -> (
        projectedCopyBytes: Int64,
        availableCapacityBytes: Int64,
        settings: AppSettings
    ) {
        let projectedCopyBytes: Int64
        switch request.projection {
        case .persistedManifest(let manifest, let supplement):
            do {
                projectedCopyBytes = try capacityProbe.conservativeProjectedBytes(
                    manifest: manifest,
                    projectionSupplement: supplement,
                    targetRootURL: request.targetRootURL
                )
            } catch {
                throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
            }
        case .liveSource(let sourceURL):
            do {
                let projection = try capacityProbe.conservativeProjectedBytes(
                    sourceURL: sourceURL,
                    targetRootURL: request.targetRootURL
                )
                projectedCopyBytes = max(projection, request.minimumProjectedBytes)
            } catch {
                throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
            }
        case .minimum:
            do {
                projectedCopyBytes = try capacityProbe.conservativeProjectedBytes(
                    minimumBytes: request.minimumProjectedBytes,
                    targetRootURL: request.targetRootURL
                )
            } catch {
                throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
            }
        }
        let availableCapacityBytes: Int64
        do {
            availableCapacityBytes = try capacityProbe.availableCapacityBytes(
                at: request.targetRootURL
            )
        } catch {
            throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
        }
        let currentSettings: AppSettings
        do {
            currentSettings = try settingsStore.loadSettings()
        } catch {
            throw VaultWriteAdmissionError.postponed(.invalidPolicy)
        }
        return (projectedCopyBytes, availableCapacityBytes, currentSettings)
    }

    /// Shared confirmation binding for the archive copy path, used before and
    /// after the admission's awaits. Compares the confirmation-time
    /// authorization against live state: trigger, `Song.id` (never conflated
    /// with the catalog `ProjectID`), source canonical path and filesystem
    /// object, active/archive root IDs, canonical paths, and filesystem
    /// objects, and `authorizedAt` ordering. A known catalog `ProjectID` must
    /// still claim the source folder; its disappearance or reassignment fails
    /// closed. A nil catalog `ProjectID` (fresh unindexed project) skips only
    /// the catalog clause. Removal-specific restrictions (backup/rollout
    /// gates, Keep Local, Emergency Stop, activity probes) are intentionally
    /// absent: they gate removal, never the copy itself.
    static func validateBoundCopyIdentity(
        authorization: ProjectVaultArchiveAuthorization,
        song: Song,
        trigger: ProjectVaultArchiveTrigger,
        request: VaultWriteAdmissionRequest?,
        settingsStore: any SettingsStore,
        catalogStore: SQLiteProjectCatalogStore,
        now: Date
    ) throws {
        guard authorization.trigger == trigger else {
            throw ProjectVaultAuthorizationError.triggerMismatch
        }
        if trigger == .backupCopy, authorization.permitsRemoval {
            throw ProjectVaultAuthorizationError.backupCopyRemovalForbidden
        }
        guard authorization.authorizedAt <= now else {
            throw ProjectVaultAuthorizationError.authorizationRequired
        }
        guard authorization.songID == song.id else {
            throw ProjectVaultAuthorizationError.songMismatch
        }
        guard authorization.sourceCanonicalPath == ProjectVaultArchiveAuthorization.canonicalPath(for: song.folderPath) else {
            throw ProjectVaultAuthorizationError.sourcePathMismatch
        }
        let liveSettings = try settingsStore.loadSettings()
        let roots = try ProjectVaultArchiveAuthorization.currentRoots(from: liveSettings)
        guard authorization.activeRootID == roots.activeID,
              authorization.activeRootCanonicalPath == roots.activePath,
              authorization.activeRootFileSystemIdentity == roots.activeIdentity,
              authorization.archiveRootID == roots.archiveID,
              authorization.archiveRootCanonicalPath == roots.archivePath,
              authorization.archiveRootFileSystemIdentity == roots.archiveIdentity else {
            throw ProjectVaultAuthorizationError.rootMismatch
        }
        let liveSourceIdentity: ProjectVaultSourceFileSystemIdentity
        do {
            liveSourceIdentity = try ProjectVaultArchiveAuthorization.fileSystemIdentity(at: song.folderPath)
        } catch {
            throw ProjectVaultAuthorizationError.sourceIdentityMismatch
        }
        guard liveSourceIdentity == authorization.sourceFileSystemIdentity else {
            throw ProjectVaultAuthorizationError.sourceIdentityMismatch
        }
        if let expectedProjectID = authorization.catalogProjectID {
            try validateBoundCatalogAssignment(
                expectedProjectID,
                sourceURL: song.folderPath,
                activeRootID: roots.activeID,
                activeRootPath: roots.activePath,
                catalogStore: catalogStore
            )
        }
        if let request {
            if let requestSourceURL = request.sourceURL {
                guard ProjectVaultArchiveAuthorization.canonicalPath(for: requestSourceURL) == authorization.sourceCanonicalPath else {
                    throw ProjectVaultAuthorizationError.sourcePathMismatch
                }
                let requestSourceIdentity: ProjectVaultSourceFileSystemIdentity
                do {
                    requestSourceIdentity = try ProjectVaultArchiveAuthorization.fileSystemIdentity(at: requestSourceURL)
                } catch {
                    throw ProjectVaultAuthorizationError.sourceIdentityMismatch
                }
                guard requestSourceIdentity == authorization.sourceFileSystemIdentity else {
                    throw ProjectVaultAuthorizationError.sourceIdentityMismatch
                }
            }
            guard ProjectVaultArchiveAuthorization.canonicalPath(for: request.targetRootURL) == authorization.archiveRootCanonicalPath else {
                throw ProjectVaultAuthorizationError.rootMismatch
            }
        }
    }

    /// Fail-closed catalog check for a previously bound catalog `ProjectID`.
    /// The folder's current claimant must be exactly the bound project; an
    /// empty claimant set (entry disappeared) or a reassignment (including an
    /// ambiguity from duplicate claims) denies rather than executing under a
    /// stale identity.
    static func validateBoundCatalogAssignment(
        _ expectedProjectID: ProjectID,
        sourceURL: URL,
        activeRootID: UUID,
        activeRootPath: String,
        catalogStore: SQLiteProjectCatalogStore
    ) throws {
        let canonicalSource = ProjectVaultArchiveAuthorization.canonicalPath(for: sourceURL)
        guard canonicalSource == activeRootPath || canonicalSource.hasPrefix(activeRootPath + "/") else {
            throw ProjectVaultAuthorizationError.catalogMismatch
        }
        let relativePath = String(canonicalSource.dropFirst(activeRootPath.count + 1))
        let entries = try catalogStore.loadEntries()
        let claimants = entries.filter { entry in
            entry.record.locations.contains {
                $0.kind == .active && $0.rootID == activeRootID && $0.relativePath == relativePath
            }
        }
        guard claimants.count == 1, claimants[0].record.id == expectedProjectID else {
            throw ProjectVaultAuthorizationError.catalogMismatch
        }
    }

    /// Copy-only denial for the compatibility `archive(song:trigger:)` path.
    /// It never authorizes removal; destructive callers must use a bound
    /// authorization via `makeBoundRemovalAdmission`.
    func makeCopyOnlyRemovalAdmission() -> LocalVaultTransferEngine.RemovalAdmission {
        { _ in throw ProjectVaultAuthorizationError.authorizationRequired }
    }

    /// Compatibility trap: the trigger alone never authorizes manual deletion.
    /// Retained for signature stability; always denies. Use
    /// `makeBoundRemovalAdmission(authorization:song:trigger:)` for bound work.
    func makeRemovalAdmission(song _: Song, trigger _: ProjectVaultArchiveTrigger) -> LocalVaultTransferEngine.RemovalAdmission {
        makeCopyOnlyRemovalAdmission()
    }

    /// Bound removal admission for authorized execution. Validates the
    /// confirmation-time authorization against live state before the volatile
    /// probes, then revalidates everything after the final await, immediately
    /// before the engine's synchronous remove (the engine invokes this
    /// callback twice, but only this post-await recheck is adjacent to the
    /// destructive operation). Live settings may only restrict: any stable
    /// gate that now forbids removal, any Keep Local/emergency change during
    /// the probe, any root ID, path, or filesystem-object change (even with
    /// an unchanged UUID or an unchanged path), any source path or
    /// filesystem-object (device/inode) change, any song/trigger/ceiling
    /// mismatch, or any catalog reassignment of the bound project denies
    /// removal.
    func makeBoundRemovalAdmission(
        authorization: ProjectVaultArchiveAuthorization,
        song: Song,
        trigger: ProjectVaultArchiveTrigger
    ) -> LocalVaultTransferEngine.RemovalAdmission {
        let settingsStore = self.settingsStore
        let catalogStore = self.catalogStore
        let activityProbe = self.activityProbe
        let now = self.now
        let executionSongID = song.id
        return { record in
            func validateBindingAndStableGates() throws {
                let liveSettings = try settingsStore.loadSettings()
                guard authorization.trigger == trigger else {
                    throw ProjectVaultAuthorizationError.triggerMismatch
                }
                if trigger == .backupCopy || authorization.trigger == .backupCopy {
                    throw ProjectVaultAuthorizationError.backupCopyRemovalForbidden
                }
                guard authorization.permitsRemoval else {
                    throw ProjectVaultAuthorizationError.removalNotAuthorized
                }
                guard authorization.authorizedAt <= now() else {
                    throw ProjectVaultAuthorizationError.authorizationRequired
                }
                guard authorization.songID == executionSongID else {
                    throw ProjectVaultAuthorizationError.songMismatch
                }
                let canonicalRecordSource = ProjectVaultArchiveAuthorization.canonicalPath(for: record.sourceURL)
                guard authorization.sourceCanonicalPath == canonicalRecordSource else {
                    throw ProjectVaultAuthorizationError.sourcePathMismatch
                }
                let roots = try ProjectVaultArchiveAuthorization.currentRoots(from: liveSettings)
                guard authorization.activeRootID == roots.activeID,
                      authorization.activeRootCanonicalPath == roots.activePath,
                      authorization.activeRootFileSystemIdentity == roots.activeIdentity,
                      authorization.archiveRootID == roots.archiveID,
                      authorization.archiveRootCanonicalPath == roots.archivePath,
                      authorization.archiveRootFileSystemIdentity == roots.archiveIdentity else {
                    throw ProjectVaultAuthorizationError.rootMismatch
                }
                if let expectedProjectID = authorization.catalogProjectID {
                    guard record.projectID == expectedProjectID else {
                        throw ProjectVaultAuthorizationError.catalogMismatch
                    }
                    try Self.validateCurrentCatalogAssignment(
                        expectedProjectID,
                        recordSourceURL: record.sourceURL,
                        activeRootID: roots.activeID,
                        activeRootPath: roots.activePath,
                        catalogStore: catalogStore
                    )
                }
                let liveIdentity: ProjectVaultSourceFileSystemIdentity
                do {
                    liveIdentity = try ProjectVaultArchiveAuthorization.fileSystemIdentity(at: record.sourceURL)
                } catch {
                    throw ProjectVaultAuthorizationError.sourceIdentityMismatch
                }
                guard liveIdentity == authorization.sourceFileSystemIdentity else {
                    throw ProjectVaultAuthorizationError.sourceIdentityMismatch
                }
                guard !liveSettings.vault.automationEmergencyStop else {
                    throw ProjectVaultRuntimeError.emergencyStop
                }
                guard liveSettings.vault.isEnabled else { throw ProjectVaultRuntimeError.disabled }
                if trigger == .manual {
                    guard liveSettings.vault.independentBackupConfirmed else {
                        throw ProjectVaultRuntimeError.independentBackupRequired
                    }
                } else {
                    guard ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(liveSettings.vault) else {
                        throw ProjectVaultRuntimeError.automaticArchivingDisabled
                    }
                }
                let keepLocalKeys = Set([
                    executionSongID,
                    authorization.songID,
                    record.projectID.description,
                    record.sourceURL.standardizedFileURL.path,
                    record.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path,
                    canonicalRecordSource,
                ])
                guard liveSettings.vault.keepLocalProjectIDs.isDisjoint(with: keepLocalKeys) else {
                    throw ProjectVaultRuntimeError.keepLocal
                }
            }
            try validateBindingAndStableGates()
            try await Self.requireProjectIdle(activityProbe, in: record.sourceURL)
            // Explicit archiving may follow a save immediately. The engine still
            // re-verifies Source and Archive bytes after the final open-file probe.
            if trigger != .manual {
                switch await activityProbe.writeActivityStatus(
                    in: record.sourceURL,
                    since: now().addingTimeInterval(-10 * 60)
                ) {
                case .clear: break
                case .busy: throw ProjectVaultRuntimeError.activityPostponed(.recentWriteActivity)
                case .uncertain(let reason): throw ProjectVaultRuntimeError.activityPostponed(.uncertainActivity(reason))
                }
            }
            // Recheck after the final await boundary: settings, Keep Local,
            // emergency, current roots (even with unchanged UUIDs), same-path
            // replacement, and the full authorization binding.
            try validateBindingAndStableGates()
        }
    }

    /// Rechecks the current catalog assignment for the bound source. The
    /// transfer record's project ID is compared against the old authorization
    /// at the call site; this additionally resolves which catalog entry
    /// claims the source folder right now and fails closed when that
    /// assignment changed, disappeared, or is ambiguous from duplicate
    /// claims. A previously bound catalog identity must never execute under
    /// a stale approval simply because no entry currently claims the folder.
    static func validateCurrentCatalogAssignment(
        _ expectedProjectID: ProjectID,
        recordSourceURL: URL,
        activeRootID: UUID,
        activeRootPath: String,
        catalogStore: SQLiteProjectCatalogStore
    ) throws {
        try validateBoundCatalogAssignment(
            expectedProjectID,
            sourceURL: recordSourceURL,
            activeRootID: activeRootID,
            activeRootPath: activeRootPath,
            catalogStore: catalogStore
        )
    }

    /// Refuses while a DAW or another program holds the project. An uncertain
    /// probe is reported as uncertainty, never as a confirmed DAW or open-file hit,
    /// so the user is not told to close a DAW that may not be running.
    static func requireProjectIdle(
        _ activityProbe: any VaultAutomationActivityProbing,
        in sourceURL: URL
    ) async throws {
        switch await activityProbe.cubaseStatus() {
        case .clear: break
        case .busy: throw ProjectVaultRuntimeError.activityPostponed(.cubaseRunning)
        case .uncertain(let reason): throw ProjectVaultRuntimeError.activityPostponed(.uncertainActivity(reason))
        }
        switch await activityProbe.openFileStatus(in: sourceURL) {
        case .clear: break
        case .busy: throw ProjectVaultRuntimeError.activityPostponed(.openFiles)
        case .uncertain(let reason): throw ProjectVaultRuntimeError.activityPostponed(.uncertainActivity(reason))
        }
    }
}
