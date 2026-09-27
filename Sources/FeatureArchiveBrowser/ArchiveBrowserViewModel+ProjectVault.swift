import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    /// Project Vault is deliberately exposed as a separate browse layer. The generic
    /// archive scanner never walks the Dropbox root. Verified generations and explicitly
    /// linked archive folders are projected from the catalog when the user asks to see them.
    var canBrowseArchivedProjects: Bool {
        projectVaultRuntime != nil && vaultObservation.context != nil
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
        // Refresh even without filesystem observation, preserving any newer Vault action's status.
        if hadPendingRestore { await scanInBackground() }
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

    /// Archived visibility toggle rebuilds the catalog from the retained
    /// snapshot list without another scan or round trip. Showing refreshes
    /// snapshots for liveness; hiding never scans.
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

    /// Thin delegate to the observation owner, which holds the snapshot
    /// index and bound-generation gating. Preserves existing callers in
    /// non-migrated files with no duplicate logic here.
    func blocksGenericProjectVaultFileActions(for song: Song) -> Bool {
        vaultObservation.blocksGenericFileActions(for: song)
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

    /// Snapshot refresh orchestration. Runtime execution and user-visible
    /// status stay here; snapshot/index/count/card storage and derivation
    /// live in `ArchiveVaultObservation`. Fail-closed semantics preserved:
    /// unavailable runtime clears to empty with no warning, while an
    /// unreadable journal preserves the current presentation and records the
    /// persistence fault.
    @discardableResult
    func refreshProjectVaultSnapshots() async -> Bool {
        guard let projectVaultRuntime else { return false }
        do {
            let snapshots = try await projectVaultRuntime.snapshots()
            if persistenceWarningMessage == Self.projectVaultReadFailureMessage {
                persistenceWarningMessage = nil
                statusMessage = combinedStatusMessage(base: statusBaseMessage)
            }
            if statusBaseMessage == ProjectVaultActivityExplanation.transfer(.awaitingProviderDurability),
               !snapshots.contains(where: { $0.transfer?.isWaitingForProviderUpload == true }) {
                setProjectVaultStatusMessage(nil)
            }
            vaultObservation.stageSnapshots(snapshots)
            rebuildProjectVaultCatalog()
            // Refresh cards even when catalog values stayed unchanged. A
            // changed catalog also prebuilds cards in `songs.willSet`, before
            // publishing the new songs.
            vaultObservation.rebuildCards(for: songs, notifyWhenChanged: false)
            // Single coalesced publish for the whole refresh (snapshots,
            // catalog, cards); silent builds above never publish.
            // `enqueueDone` may enqueue and publish separately through the
            // operation owner, preserving existing timing.
            objectWillChange.send()
            enqueueDoneVaultProjectsIfNeeded()
            await scheduleProjectVaultRecovery()
            return true
        } catch ProjectVaultRuntimeError.unavailable {
            vaultObservation.cancelRecovery()
            vaultObservation.stageSnapshots([])
            rebuildProjectVaultCatalog()
            vaultObservation.rebuildCards(for: songs, notifyWhenChanged: false)
            objectWillChange.send()
            return false
        } catch {
            vaultObservation.cancelRecovery()
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

    /// Recovery scheduling orchestration. Fetches the due date from the
    /// runtime (execution stays here) and delegates timer lifecycle,
    /// deduplication, and 30-second backoff to the observation owner with
    /// narrow weak callbacks. The owner never retains this view model.
    func scheduleProjectVaultRecovery() async {
        guard let projectVaultRuntime else {
            vaultObservation.cancelRecovery()
            return
        }
        guard projectVaultBusySongIDs.isEmpty else { return }
        let due = try? await projectVaultRuntime.nextAutomaticRecoveryDate()
        vaultObservation.scheduleRecovery(
            isBusy: { [weak self] in self?.projectVaultBusySongIDs.isEmpty == false },
            dueDate: due,
            recover: { [projectVaultRuntime] in
                await projectVaultRuntime.recoverAtLaunch()
            },
            didRecover: { [weak self] in
                await self?.refreshProjectVaultSnapshots()
            }
        )
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
            // Gating lives in the observation owner (pin OR over all key
            // forms, runtime pin, presentation pin, and catalog Active-location
            // matches); this loop stays as composition.
            if vaultObservation.isIntentionalKeepLocalSkip(for: song) { continue }
            let transfer = projectVaultSnapshot(for: song)?.transfer
            if transfer != nil {
                // A persisted transfer releases any capacity postponement
                // recorded for this song; recovery/manual review owns next steps.
                vaultOperations.releaseCapacityPostponement(for: song.id)
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
}
