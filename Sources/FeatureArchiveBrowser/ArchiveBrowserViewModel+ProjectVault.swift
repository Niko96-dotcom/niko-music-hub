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
        let hadPendingRestore = (try? await projectVaultRuntime.snapshots())?.contains { $0.restore != nil } ?? false
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
            return "Use Get Local & Open to choose a version and restore this project."
        case .revealArchive:
            return "Use Show in Finder to access this archive. Project versions cannot be opened directly here."
        case .openInCubase, .retry, .review:
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
            projectVaultSnapshots = snapshots
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
            diagnostics.log(.error, "Project Vault state refresh failed: \(error)")
            return false
        }
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
            let transfer = projectVaultSnapshot(for: song)?.transfer
            // A persisted transfer—terminal, in progress, or failed—is owned by
            // recovery/manual review. Never create another automatic generation
            // merely because the project remains marked Done. The nil
            // authorization here is always copy-only; removal needs a fresh
            // explicit confirmation and a revoked approval is never reused.
            if transfer == nil,
               !projectVaultBusySongIDs.contains(song.id),
               projectVaultRetryTasks[song.id] == nil {
                archiveInProjectVault(song, trigger: .workflowDone)
            }
        }
    }

    private func isBlockedByUnresolvedIdentityReview(_ song: Song) -> Bool {
        guard let presented = identityReviewPresentation,
              let bound = presented.song else { return false }
        return bound.id == song.id
    }
}
