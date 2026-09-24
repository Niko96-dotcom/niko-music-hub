import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    /// Project Vault is deliberately exposed as a separate browse layer. The generic
    /// archive scanner never walks the Dropbox root. Verified generations and explicitly
    /// linked archive folders are projected from the catalog when the user asks to see them.
    var canBrowseArchivedProjects: Bool {
        projectVaultRuntime != nil && projectVaultPresentationContext != nil
    }

    func recoverProjectVaultAndRefresh() async {
        guard let projectVaultRuntime else { return }
        let hadPendingRestore: Bool
        do {
            hadPendingRestore = try await projectVaultRuntime.snapshots().contains { $0.restore != nil }
        } catch ProjectVaultRuntimeError.unavailable {
            await refreshProjectVaultSnapshots()
            return
        } catch {
            // Recovery must not treat an unreadable transfer journal as empty.
            // Preserve the current presentation and show the persistence fault.
            recordProjectVaultReadFailure(error, context: "Project Vault recovery preflight failed")
            return
        }
        await projectVaultRuntime.recoverAtLaunch()
        await refreshProjectVaultSnapshots()
        // Recovery can create an Active folder after the initial scan completed.
        // Refresh explicitly even when filesystem observation is unavailable.
        if hadPendingRestore { await scan() }
    }

    /// Applies a Project Vault setup change to the already-mounted Archive Browser.
    /// Settings owns persistence; this method deliberately reloads the effective scan roots,
    /// restarts observation, and refreshes vault recovery/snapshots without requiring a relaunch.
    public func applyProjectVaultSettingsChange() {
        guard !runtime.usesFixtureRoot else {
            refreshProjectVaultPresentationContext()
            rebuildProjectVaultCatalog()
            Task {
                await recoverProjectVaultAndRefresh()
            }
            return
        }

        let previousRoots = roots.standardizedArchivePaths
        loadRootsFromSettings()
        refreshProjectVaultPresentationContext()
        let rootsChanged = previousRoots != roots.standardizedArchivePaths

        if rootsChanged {
            clearRootBoundArchiveState(
                statusMessage: roots.isEmpty
                    ? "Project Vault settings updated. Add an Active Projects root to scan."
                    : "Project Vault settings updated. Scanning Active Projects…"
            )
            restartArchiveRootWatching()
            if !roots.isEmpty {
                Task { await scanInBackground() }
            }
        } else {
            rebuildProjectVaultCatalog()
        }

        Task {
            await recoverProjectVaultAndRefresh()
        }
    }

    func setShowArchivedProjects(_ isShown: Bool) {
        guard showArchivedProjects != isShown else {
            if isShown {
                Task { await refreshProjectVaultSnapshots() }
            }
            return
        }
        showArchivedProjects = isShown
        rebuildProjectVaultCatalog()
        if isShown {
            Task { await refreshProjectVaultSnapshots() }
        }
    }

    func isArchivedProject(_ song: Song) -> Bool {
        projectVaultPresentation(for: song)?.state == .archived
    }

    func projectOpenBlockReason(for song: Song) -> String? {
        guard blocksGenericProjectVaultFileActions(for: song) else { return nil }
        guard let presentation = projectVaultPresentation(for: song) else {
            return "Check this project's storage in Project Vault before opening a version."
        }
        switch presentation.primaryAction {
        case .restoreAndOpen:
            return "Use Restore & Open to choose a version and restore this project."
        case .revealArchive:
            return "Use Show in Finder to access this archive. Project versions cannot be opened directly here."
        case .openInCubase, .retry, .review, .freeUpSpace:
            return presentation.explanation
        }
    }

    /// Project Vault destinations are restore/review handles, never generic
    /// filesystem authority. Source-path cards also stay non-actionable while a
    /// destructive or binding review owns the project, even if the source path
    /// happens to reappear before the next catalog rebuild.
    func blocksGenericProjectVaultFileActions(for song: Song) -> Bool {
        guard let snapshot = projectVaultSnapshot(for: song) else {
            return false
        }
        let songPath = Self.vaultCanonicalPath(song.folderPath)
        if let linked = linkedArchive(for: snapshot), songPath == Self.vaultCanonicalPath(linked.url) {
            return true
        }
        if let restore = snapshot.restore,
           restore.projectID == snapshot.record.id,
           restore.completedAt == nil,
           songPath == Self.vaultCanonicalPath(restore.destinationURL) {
            return true
        }
        guard let transfer = snapshot.transfer else { return false }
        let isSourcePath = songPath == Self.vaultCanonicalPath(transfer.sourceURL)
        let isDestinationPath = songPath == Self.vaultCanonicalPath(transfer.destinationURL)
        guard isSourcePath || isDestinationPath else { return false }

        let terminalDestinationBlocks = isDestinationPath && [
            VaultTransferState.archiveVerified,
            .archivedLocal,
            .archivedOnlineOnly,
        ].contains(transfer.state)
        let restoreBlocks = snapshot.restore.map {
            $0.failureReason == .archiveTransferBindingUnavailable
                || $0.failureReason == .activeDestinationIntegrityMismatch
                || $0.phase == .superseded
                || $0.supersededBy != nil
        } ?? false
        let incompletePostPromotionRestoreBlocks = snapshot.restore.map {
            guard $0.completedAt == nil else { return false }
            return $0.phase == .persistingActiveLocation || $0.phase == .openingInCubase
        } ?? false
        let destructiveRecoveryBlocks = transfer.state == .recoveryRequired
            && (transfer.error?.origin == .removingActiveCopy
                || transfer.error?.origin == .evictingProviderCache)
        let supersededTransferBlocks = transfer.state == .superseded
            || transfer.supersededBy != nil
        return terminalDestinationBlocks
            || restoreBlocks
            || incompletePostPromotionRestoreBlocks
            || destructiveRecoveryBlocks
            || supersededTransferBlocks
    }

    func canMutateWorkflowStatus(for song: Song) -> Bool {
        guard !blocksGenericProjectVaultFileActions(for: song) else { return false }
        return ProjectVaultCardWorkflowPolicy.allowsWorkflowMutation(
            for: projectVaultPresentation(for: song)
        )
    }

    func canArchiveInProjectVault(_ song: Song) -> Bool {
        guard projectVaultRuntime != nil,
              !blocksGenericProjectVaultFileActions(for: song),
              projectVaultPresentation(for: song)?.state != .archived else { return false }
        if let restore = projectVaultSnapshot(for: song)?.restore,
           restore.completedAt == nil {
            return false
        }
        if let transfer = projectVaultSnapshot(for: song)?.transfer,
           VaultTransferOwnershipPolicy.ownsProject(transfer.state) {
            return false
        }
        return !projectVaultBusySongIDs.contains(song.id)
    }

    func setProjectKeepLocal(_ keepLocal: Bool, for song: Song) {
        do {
            let key = projectVaultSnapshot(for: song)?.transfer?.sourceURL.path ?? song.id
            try settingsStore.updateSettings { settings in
                if keepLocal { settings.vault.keepLocalProjectIDs.insert(key) }
                else { settings.vault.keepLocalProjectIDs.remove(key) }
            }
            refreshProjectVaultPresentationContext()
        } catch {
            diagnostics.log(.error, "Project Vault Keep Local setting failed: \(error)")
            setProjectVaultStatusMessage("Keep Local could not be saved. No project files were changed.")
        }
    }

    @discardableResult
    func refreshProjectVaultSnapshots() async -> Bool {
        guard let projectVaultRuntime else { return false }
        do {
            let snapshots = try await projectVaultRuntime.snapshots()
            if persistenceWarningMessage == Self.projectVaultReadFailureMessage {
                persistenceWarningMessage = nil
                statusMessage = combinedStatusMessage(base: statusBaseMessage)
            }
            projectVaultSnapshots = snapshots
            if statusBaseMessage == ProjectVaultActivityExplanation.transfer(.awaitingProviderDurability),
               !snapshots.contains(where: { $0.transfer?.isWaitingForProviderUpload == true }) {
                setProjectVaultStatusMessage(nil)
            }
            projectVaultSnapshotsByPath.removeAll()
            snapshots.forEach(cacheProjectVaultSnapshot)
            archivedProjectCount = archivedOnlySnapshots(from: snapshots).count
            rebuildProjectVaultCatalog()
            rebuildProjectVaultPresentationCache()
            enqueueDoneVaultProjectsIfNeeded()
            await scheduleProjectVaultRecovery()
            return true
        } catch ProjectVaultRuntimeError.unavailable {
            cancelProjectVaultRecovery()
            projectVaultSnapshots = []
            projectVaultSnapshotsByPath.removeAll()
            archivedProjectCount = 0
            rebuildProjectVaultCatalog()
            rebuildProjectVaultPresentationCache()
            return false
        } catch {
            cancelProjectVaultRecovery()
            recordProjectVaultReadFailure(error, context: "Project Vault state refresh failed")
            return false
        }
    }

    static let projectVaultReadFailureMessage = "Project Vault status couldn't be read. Nothing was changed."

    /// Plain footer copy for an unreadable Vault state; the technical detail
    /// goes to diagnostics only. While settings themselves are unreadable the
    /// Vault read fails for that reason, and the settings-repair notice
    /// already explains it, so nothing is added here.
    func recordProjectVaultReadFailure(_ error: any Error, context: String) {
        diagnostics.log(.error, "\(context): \(error)")
        if (try? settingsStore.loadSettings()) == nil { return }
        recordPersistenceWarning(Self.projectVaultReadFailureMessage)
    }

    func scheduleProjectVaultRecovery() async {
        guard projectVaultBusySongIDs.isEmpty else { return }
        guard let projectVaultRuntime,
              let due = try? await projectVaultRuntime.nextAutomaticRecoveryDate() else {
            cancelProjectVaultRecovery()
            return
        }
        // A busy mutation lease or unavailable provider can leave the due date
        // unchanged. Back off locally instead of spinning on an overdue record.
        let deadline = max(due, projectVaultLastRecoveryAttemptAt?.addingTimeInterval(30) ?? due)
        guard projectVaultRecoveryDeadline != deadline else { return }
        cancelProjectVaultRecovery()
        projectVaultRecoveryDeadline = deadline
        projectVaultRecoveryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            } catch { return }
            guard let self, !Task.isCancelled else { return }
            guard self.projectVaultBusySongIDs.isEmpty else {
                self.projectVaultRecoveryTask = nil
                self.projectVaultRecoveryDeadline = nil
                return
            }
            self.projectVaultLastRecoveryAttemptAt = Date()
            await projectVaultRuntime.recoverAtLaunch()
            guard !Task.isCancelled else { return }
            self.projectVaultRecoveryTask = nil
            self.projectVaultRecoveryDeadline = nil
            await self.refreshProjectVaultSnapshots()
        }
    }

    private func cancelProjectVaultRecovery() {
        projectVaultRecoveryTask?.cancel()
        projectVaultRecoveryTask = nil
        projectVaultRecoveryDeadline = nil
    }

    private func enqueueDoneVaultProjectsIfNeeded() {
        for song in songs where song.workflowStatus == .done {
            // P2: an unresolved identity sheet promises "Nothing is archived
            // until you choose." Never auto-archive the exact song that owns
            // the presented review. Stable song binding only (songID); never
            // titles. Unrelated Done songs keep their automatic copy, and
            // explicit resolution clears the presentation so the next refresh
            // resumes normally via the fresh-confirmation path.
            if isBlockedByUnresolvedIdentityReview(song) { continue }
            // Intentional Keep Local pins never auto-archive: skip silently so
            // relaunch, queue-drain, and other-copy refreshes enqueue nothing,
            // record no failure, and leave the footer alone. Explicit manual
            // archiving still runs runtime admission and reports its actionable
            // Keep Local error; only the automatic path is quieted here.
            if isIntentionalKeepLocalForAutomaticDoneSkip(song) { continue }
            let transfer = projectVaultSnapshot(for: song)?.transfer
            if transfer != nil {
                // A persisted transfer releases any capacity postponement
                // recorded for this song; recovery/manual review owns next steps.
                projectVaultCapacityPostponedSongIDs.remove(song.id)
            }
            // A persisted transfer—terminal, in progress, or failed—is owned by
            // recovery/manual review. Never create another automatic generation
            // merely because the project remains marked Done. The nil
            // authorization here is always copy-only; removal needs a fresh
            // explicit confirmation and a revoked approval is never reused.
            // A Done song already postponed for non-retryable destination
            // capacity stays quiet until a manual attempt, success, or undo
            // clears it: otherwise every snapshots refresh (launch recovery,
            // settings changes, the recovery timer) would immediately
            // re-attempt a destination known to be full.
            if transfer == nil,
               !projectVaultBusySongIDs.contains(song.id),
               projectVaultRetryTasks[song.id] == nil,
               !projectVaultCapacityPostponedSongIDs.contains(song.id) {
                archiveInProjectVault(song, trigger: .workflowDone)
            }
        }
    }

    private func isBlockedByUnresolvedIdentityReview(_ song: Song) -> Bool {
        guard let presented = identityReviewPresentation,
              let bound = presented.song else { return false }
        return bound.id == song.id
    }

    /// Keep Local detection for the automatic Done path, using the same
    /// identity/path keys as the snapshot and presentation logic: the catalog
    /// project ID, the song ID, and the transfer source path in raw,
    /// standardized, and resolved form, plus the runtime `pinned` flag (which
    /// already agrees with what removal admission would refuse) and the
    /// prepared presentation pin. Every source is OR-ed; a settings-only
    /// check never clears a runtime pin.
    private func isIntentionalKeepLocalForAutomaticDoneSkip(_ song: Song) -> Bool {
        guard let context = projectVaultPresentationContext else { return false }
        let keepLocal = context.keepLocalProjectIDs
        if keepLocal.contains(song.id) { return true }
        let songPathKeys: Set<String> = [
            song.folderPath.path,
            song.folderPath.standardizedFileURL.path,
            song.folderPath.standardizedFileURL.resolvingSymlinksInPath().path,
            Self.vaultCanonicalPath(song.folderPath),
        ]
        if !keepLocal.isDisjoint(with: songPathKeys) { return true }
        if let snapshot = projectVaultSnapshot(for: song) {
            if snapshot.record.pinned { return true }
            if keepLocal.contains(snapshot.record.id.description) { return true }
            if Self.isKeepLocalPinned(context: context, snapshot: snapshot, song: song) { return true }
        }
        if projectVaultPresentation(for: song)?.isKeepLocal == true { return true }
        return snapshotsContainKeepLocalMatch(for: song, context: context, keepLocal: keepLocal)
    }

    /// Catalog snapshots that are not path-cached (no transfer, no linked
    /// archive) still carry the runtime pin and record ID. Match them to the
    /// song by canonical Active location so a Keep Local pin stored under the
    /// catalog project ID also skips the automatic Done copy.
    private func snapshotsContainKeepLocalMatch(
        for song: Song,
        context: ProjectVaultPresentationContext,
        keepLocal: Set<String>
    ) -> Bool {
        guard let activeRoot = context.activeRoot else { return false }
        let songPath = Self.vaultCanonicalPath(song.folderPath)
        let activeBase = activeRoot.fallbackURL.standardizedFileURL.resolvingSymlinksInPath()
        for snapshot in projectVaultSnapshots {
            guard snapshot.record.pinned || keepLocal.contains(snapshot.record.id.description) else { continue }
            for location in snapshot.record.locations
                where location.kind == .active && location.rootID == activeRoot.id {
                let candidate = activeBase.appendingPathComponent(location.relativePath, isDirectory: true)
                if Self.vaultCanonicalPath(candidate) == songPath { return true }
            }
        }
        return false
    }
}
