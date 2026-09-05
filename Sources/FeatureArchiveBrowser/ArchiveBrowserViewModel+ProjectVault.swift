import AppCore
import Foundation
import NikoMusicCore

/// The small, immutable subset of settings that determines Project Vault card
/// state. It is loaded once while refreshing the presentation cache, never from
/// a SwiftUI card render.
struct ProjectVaultPresentationContext: Equatable {
    let activeRoot: StoredMusicRoot?
    let archiveRoot: StoredMusicRoot?
    let generationReviewResolver: ProjectVaultGenerationReviewResolver?
    let keepLocalProjectIDs: Set<String>

    init?(settings: AppSettings) {
        guard settings.vault.isEnabled else { return nil }
        activeRoot = settings.musicRoots.first { $0.id == settings.vault.activeRootID }
        archiveRoot = settings.musicRoots.first { $0.id == settings.vault.archiveRootID }
        generationReviewResolver = ProjectVaultGenerationReviewResolver(settings: settings)
        keepLocalProjectIDs = settings.vault.keepLocalProjectIDs
    }
}

/// Archive-only Project Vault cards are restore targets, not workflow inputs.
/// Keeping this decision shared between card surfaces and the view model prevents
/// drag/drop or menu affordances from bypassing the same safety boundary.
enum ProjectVaultCardWorkflowPolicy {
    static func allowsWorkflowMutation(for presentation: ProjectVaultCardPresentation?) -> Bool {
        guard let presentation else { return true }
        switch presentation.state {
        case .active, .keepLocal:
            return true
        case .archived, .restoring, .archiving, .needsAttention:
            return false
        }
    }
}

extension ArchiveBrowserViewModel {
    /// Applies a Project Vault setup change to the already-mounted Archive Browser.
    /// Settings owns persistence; this method deliberately reloads the effective scan roots,
    /// restarts observation, and refreshes vault recovery/snapshots without requiring a relaunch.
    public func applyProjectVaultSettingsChange() {
        guard !runtime.usesFixtureRoot else {
            refreshProjectVaultPresentationContext()
            Task {
                await projectVaultRuntime?.recoverAtLaunch()
                await refreshProjectVaultSnapshots()
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
            await projectVaultRuntime?.recoverAtLaunch()
            await refreshProjectVaultSnapshots()
        }
    }

    /// Project Vault is deliberately exposed as a separate browse layer. The generic
    /// archive scanner never walks the Dropbox root, but a verified vault snapshot can
    /// still project an archive-only project into the Hub when the user asks to see it.
    var canBrowseArchivedProjects: Bool {
        projectVaultRuntime != nil && projectVaultPresentationContext != nil
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

    /// Project Vault destinations are restore/review handles, never generic
    /// filesystem authority. Source-path cards also stay non-actionable while a
    /// destructive or binding review owns the project, even if the source path
    /// happens to reappear before the next catalog rebuild.
    func blocksGenericProjectVaultFileActions(for song: Song) -> Bool {
        guard let snapshot = projectVaultSnapshot(for: song) else {
            return false
        }
        let songPath = Self.vaultCanonicalPath(song.folderPath)
        if let restore = snapshot.restore,
           restore.projectID == snapshot.record.id,
           restore.failureReason == .activeDestinationIntegrityMismatch,
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

    func projectVaultPresentation(for song: Song) -> ProjectVaultCardPresentation? {
        projectVaultPresentationsBySongID[song.id]
    }

    /// Loads the narrow settings context at an explicit settings boundary, then
    /// rebuilds the card map. The render path itself never calls `SettingsStore`.
    func refreshProjectVaultPresentationContext(notifyWhenChanged: Bool = true) {
        let nextContext = (try? settingsStore.loadSettings())
            .flatMap(ProjectVaultPresentationContext.init(settings:))
        let contextChanged = nextContext != projectVaultPresentationContext
        projectVaultPresentationContext = nextContext
        let presentationsChanged = rebuildProjectVaultPresentationCache(notifyWhenChanged: false)
        if notifyWhenChanged && (contextChanged || presentationsChanged) {
            objectWillChange.send()
        }
    }

    /// Rebuilds immutable card data at a catalog or snapshot boundary. This is
    /// intentionally internal: `songs` is owned in the primary view-model file
    /// and calls this before it publishes a replacement catalog.
    @discardableResult
    func rebuildProjectVaultPresentationCache(
        for songs: [Song]? = nil,
        notifyWhenChanged: Bool = true
    ) -> Bool {
        let context = projectVaultPresentationContext
        let cacheSongs = songs ?? self.songs
        var nextPresentations: [String: ProjectVaultCardPresentation] = [:]
        nextPresentations.reserveCapacity(cacheSongs.count)
        if let context {
            for song in cacheSongs {
                if let presentation = makeProjectVaultPresentation(for: song, context: context) {
                    // Catalogs are normally de-duplicated before publication. Keep
                    // this assignment safe for malformed/manual test input too.
                    nextPresentations[song.id] = presentation
                }
            }
        }

        guard nextPresentations != projectVaultPresentationsBySongID else {
            return false
        }
        projectVaultPresentationsBySongID = nextPresentations
        if notifyWhenChanged {
            objectWillChange.send()
        }
        return true
    }

    private func makeProjectVaultPresentation(
        for song: Song,
        context: ProjectVaultPresentationContext
    ) -> ProjectVaultCardPresentation? {
        if let snapshot = projectVaultSnapshot(for: song) {
            var record = snapshot.record
            record.pinned = context.keepLocalProjectIDs.contains(snapshot.transfer?.sourceURL.path ?? song.id)
            let transferState = snapshot.transfer?.state == .archiveVerified ? nil : snapshot.transfer?.state
            let safeRestore = snapshot.restore.flatMap { restore -> VaultRestoreRecord? in
                if restore.failureReason == .archiveTransferBindingUnavailable
                    || restore.failureReason == .activeDestinationIntegrityMismatch
                    || restore.phase == .superseded
                    || restore.supersededBy != nil {
                    return restore
                }
                guard let transferID = restore.archiveTransferID,
                      context.generationReviewResolver?.isBoundGenerationPath(
                        restore.archiveGenerationURL,
                        projectID: restore.projectID,
                        transferID: transferID
                      ) == true else {
                    return nil
                }
                return restore
            }
            let terminalStates: Set<VaultTransferState> = [
                .archiveVerified, .archivedLocal, .archivedOnlineOnly,
            ]
            let hasBoundTerminalGeneration = snapshot.transfer.map { transfer in
                terminalStates.contains(transfer.state)
                    && context.generationReviewResolver?.isBoundGenerationPath(
                        transfer.destinationURL,
                        projectID: transfer.projectID,
                        transferID: transfer.id
                    ) == true
            } ?? false
            let hasUnsafeTransferGeneration = snapshot.transfer.map { transfer in
                terminalStates.contains(transfer.state) && !hasBoundTerminalGeneration
            } ?? false
            if hasBoundTerminalGeneration,
               let transfer = snapshot.transfer,
               let archiveRoot = context.archiveRoot,
               !record.locations.contains(where: {
                   $0.kind == .archive && $0.availability != .missing
               }) {
                record.locations.append(ProjectLocation(
                    rootID: archiveRoot.id,
                    relativePath: transfer.destinationURL.path,
                    kind: .archive,
                    availability: transfer.state == .archivedOnlineOnly ? .onlineOnly : .local
                ))
            }
            let isArchiveDestinationProjection = snapshot.transfer.map {
                Self.vaultCanonicalPath(song.folderPath)
                    == Self.vaultCanonicalPath($0.destinationURL)
            } ?? false
            if (snapshot.restore != nil && safeRestore == nil)
                || (hasUnsafeTransferGeneration && isArchiveDestinationProjection) {
                return ProjectVaultCardPresentation(
                    record: record,
                    transferState: .recoveryRequired
                )
            }
            return ProjectVaultCardPresentation(
                record: record,
                transferState: transferState,
                transferErrorOrigin: snapshot.transfer?.error?.origin,
                restorePhase: safeRestore?.phase,
                restore: safeRestore
            )
        }
        guard let active = context.activeRoot else { return nil }
        let path = song.folderPath.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.vaultContains(active.fallbackURL, path) else { return nil }
        let record = ProjectRecord(
            canonicalTitle: song.effectiveDisplayTitle,
            locations: [ProjectLocation(rootID: active.id, relativePath: song.folderPath.lastPathComponent, kind: .active)],
            pinned: context.keepLocalProjectIDs.contains(song.id),
            workflowState: song.workflowStatus,
            lastActivityAt: song.effectiveLatestCPR?.modifiedAt
        )
        return ProjectVaultCardPresentation(record: record)
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

    func archiveInProjectVault(_ song: Song, trigger: ProjectVaultArchiveTrigger = .manual) {
        guard let projectVaultRuntime,
              canArchiveInProjectVault(song),
              !projectVaultBusySongIDs.contains(song.id) else { return }
        projectVaultBusySongIDs.insert(song.id)
        setProjectVaultStatusMessage(trigger == .workflowDone ? "Done — checking Project Vault safety…" : "Archiving and verifying a Project Vault copy…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.projectVaultBusySongIDs.remove(song.id) }
            do {
                let snapshot = try await projectVaultRuntime.archive(song: song, trigger: trigger)
                self.projectVaultRetryTasks.removeValue(forKey: song.id)?.cancel()
                self.projectVaultRetryAttemptCounts.removeValue(forKey: song.id)
                self.cacheProjectVaultSnapshot(snapshot)
                self.rebuildProjectVaultPresentationCache()
                await self.refreshProjectVaultSnapshots()
                let activeRetained = FileManager.default.fileExists(atPath: song.folderPath.path)
                self.setProjectVaultStatusMessage(activeRetained
                    ? "Backup copy verified. The project remains in Active Projects."
                    : "Archived and verified. Find this song in Show archived projects to restore it.")
            } catch let error as ProjectVaultRuntimeError where trigger == .workflowDone {
                _ = await self.refreshProjectVaultSnapshots()
                self.setProjectVaultStatusMessage("Marked Done. \(error.localizedDescription)")
                self.diagnostics.log(.warning, "Done auto-archive postponed: \(error)")
                if case .activityPostponed(let reason) = error,
                   reason.permitsBoundedAutomaticRetry {
                    self.scheduleDoneArchiveRetry(for: song)
                }
            } catch {
                _ = await self.refreshProjectVaultSnapshots()
                self.setProjectVaultStatusMessage("Archive did not complete: \(error.localizedDescription)")
                self.diagnostics.log(.error, "Project Vault archive failed: \(error)")
            }
        }
    }

    func performProjectVaultPrimaryAction(for song: Song) {
        guard let presentation = projectVaultPresentation(for: song) else {
            try? openLatestCPR(for: song)
            return
        }
        switch presentation.primaryAction {
        case .openInCubase:
            try? openLatestCPR(for: song)
        case .restoreAndOpen:
            restoreAndOpenFromProjectVault(song)
        case .retry:
            retryProjectVaultTransfer(song)
        case .review:
            if case .makeAvailableOfflineInFinder(let generationURL) = presentation.reviewAction {
                setProjectVaultStatusMessage(
                    "Make this exact archive generation available offline in Finder, then choose Retry Get Local."
                )
                revealProjectVaultGenerationInFinder(generationURL, for: song)
            } else {
                setProjectVaultStatusMessage(presentation.explanation)
            }
        }
    }

    private func revealProjectVaultGenerationInFinder(_ generationURL: URL, for song: Song) {
        do {
            let settings = try settingsStore.loadSettings()
            guard let restore = projectVaultSnapshot(for: song)?.restore,
                  let transferID = restore.archiveTransferID else {
                throw MusicItemOpenerError.pathOutsideAllowedRoots(
                    generationURL.standardizedFileURL
                )
            }
            guard let resolver = ProjectVaultGenerationReviewResolver(settings: settings),
                  let resolved = resolver.resolveGeneration(
                    generationURL,
                    projectID: restore.projectID,
                    transferID: transferID
                  ) else {
                throw MusicItemOpenerError.pathOutsideAllowedRoots(
                    generationURL.standardizedFileURL
                )
            }
            fileActions.revealInFinder(resolved)
        } catch let error as MusicItemOpenerError {
            setProjectVaultStatusMessage(musicItemOpenerStatusMessage(error))
            diagnostics.log(.warning, "Project Vault generation reveal refused: \(error)")
        } catch {
            setProjectVaultStatusMessage(
                "Project Vault generation cannot be revealed: \(error.localizedDescription)"
            )
            diagnostics.log(.warning, "Project Vault generation reveal failed: \(error)")
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

    private func cancelProjectVaultRecovery() {
        projectVaultRecoveryTask?.cancel()
        projectVaultRecoveryTask = nil
        projectVaultRecoveryDeadline = nil
    }

    private func scheduleProjectVaultRecovery() async {
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
            self.projectVaultLastRecoveryAttemptAt = Date()
            await projectVaultRuntime.recoverAtLaunch()
            guard !Task.isCancelled else { return }
            self.projectVaultRecoveryTask = nil
            self.projectVaultRecoveryDeadline = nil
            await self.refreshProjectVaultSnapshots()
        }
    }

    private func enqueueDoneVaultProjectsIfNeeded() {
        for song in songs where song.workflowStatus == .done {
            let transfer = projectVaultSnapshot(for: song)?.transfer
            // A persisted transfer—terminal, in progress, or failed—is owned by
            // recovery/manual review. Never create another automatic generation
            // merely because the project remains marked Done.
            if transfer == nil,
               !projectVaultBusySongIDs.contains(song.id),
               projectVaultRetryTasks[song.id] == nil {
                archiveInProjectVault(song, trigger: .workflowDone)
            }
        }
    }

    private func scheduleDoneArchiveRetry(for song: Song) {
        let attemptCount = projectVaultRetryAttemptCounts[song.id, default: 0]
        guard projectVaultRetryTasks[song.id] == nil, attemptCount < 3 else { return }
        projectVaultRetryAttemptCounts[song.id] = attemptCount + 1
        projectVaultRetryTasks[song.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled else { return }
            self.projectVaultRetryTasks.removeValue(forKey: song.id)
            guard let current = self.songs.first(where: { $0.id == song.id }),
                  current.workflowStatus == .done else { return }
            self.archiveInProjectVault(current, trigger: .workflowDone)
        }
    }

    private func restoreAndOpenFromProjectVault(_ song: Song) {
        guard let runtime = projectVaultRuntime, let snapshot = projectVaultSnapshot(for: song) else {
            setProjectVaultStatusMessage("Restore is unavailable because no verified Project Vault generation was found.")
            return
        }
        guard !projectVaultBusySongIDs.contains(song.id) else { return }
        projectVaultBusySongIDs.insert(song.id)
        setProjectVaultStatusMessage("Restoring the verified project into Active Projects…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.projectVaultBusySongIDs.remove(song.id) }
            do {
                _ = try await runtime.restoreAndOpen(snapshot: snapshot)
                await self.refreshProjectVaultSnapshots()
                await self.scan()
                self.setProjectVaultStatusMessage("Restored and verified in Active Projects. Sent to its DAW to open; check any project or plug-in prompts there.")
            } catch {
                _ = await self.refreshProjectVaultSnapshots()
                self.setProjectVaultStatusMessage("Restore stopped safely: \(error.localizedDescription). The archive copy was kept.")
                self.diagnostics.log(.error, "Project Vault restore failed: \(error)")
            }
        }
    }

    private func retryProjectVaultTransfer(_ song: Song) {
        guard let runtime = projectVaultRuntime, let snapshot = projectVaultSnapshot(for: song) else {
            setProjectVaultStatusMessage("Retry is unavailable because no recoverable Project Vault transfer was found.")
            return
        }
        guard !projectVaultBusySongIDs.contains(song.id) else { return }
        projectVaultBusySongIDs.insert(song.id)
        setProjectVaultStatusMessage("Retrying the preserved Project Vault transfer…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.projectVaultBusySongIDs.remove(song.id) }
            do {
                let updated = try await runtime.retry(snapshot: snapshot)
                self.cacheProjectVaultSnapshot(updated)
                self.rebuildProjectVaultPresentationCache()
                if await self.refreshProjectVaultSnapshots() {
                    self.setProjectVaultStatusMessage("Backup copy verified. Choose Archive Now to remove the Active copy after its safety checks.")
                } else {
                    self.setProjectVaultStatusMessage("Project Vault retry completed, but the current Vault state could not be refreshed. Review before taking another action.")
                }
            } catch {
                _ = await self.refreshProjectVaultSnapshots()
                self.setProjectVaultStatusMessage("Project Vault retry stopped safely: \(error.localizedDescription). Existing copies were kept.")
                self.diagnostics.log(.error, "Project Vault manual retry failed: \(error)")
            }
        }
    }

    func retryReviewedProjectVaultRestore(for song: Song) {
        guard let runtime = projectVaultRuntime,
              let restoreID = projectVaultPresentation(for: song)?.retryRestoreID else {
            setProjectVaultStatusMessage(
                "Restore retry is unavailable because no preserved Project Vault restore was found."
            )
            return
        }
        guard !projectVaultBusySongIDs.contains(song.id) else { return }
        projectVaultBusySongIDs.insert(song.id)
        setProjectVaultStatusMessage("Retrying this preserved Project Vault restore…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.projectVaultBusySongIDs.remove(song.id) }
            do {
                let completed = try await runtime.retryRestore(id: restoreID)
                guard completed.id == restoreID,
                      completed.completedAt != nil,
                      completed.failureReason == nil else {
                    throw ProjectVaultRuntimeError.unavailable
                }
                if await self.refreshProjectVaultSnapshots() {
                    await self.scan()
                    self.setProjectVaultStatusMessage(
                        "Project Vault restore retry completed and verified."
                    )
                } else {
                    self.setProjectVaultStatusMessage(
                        "Project Vault restore retry completed, but the current Vault state could not be refreshed. Review before taking another action."
                    )
                }
            } catch {
                _ = await self.refreshProjectVaultSnapshots()
                self.setProjectVaultStatusMessage(
                    "Project Vault restore retry stopped safely: \(error.localizedDescription). Existing copies were kept."
                )
                self.diagnostics.log(.error, "Project Vault restore retry failed: \(error)")
            }
        }
    }

    private func projectVaultSnapshot(for song: Song) -> ProjectVaultRuntimeSnapshot? {
        projectVaultSnapshotsByPath[Self.vaultCanonicalPath(song.folderPath)]
    }

    private func cacheProjectVaultSnapshot(_ snapshot: ProjectVaultRuntimeSnapshot) {
        if let restore = snapshot.restore,
           restore.projectID == snapshot.record.id,
           restore.failureReason == .activeDestinationIntegrityMismatch,
           let activeRoot = projectVaultPresentationContext?.activeRoot {
            let activeRootURL = activeRoot.fallbackURL
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let destinationURL = restore.destinationURL
                .standardizedFileURL
                .resolvingSymlinksInPath()
            if destinationURL != activeRootURL,
               Self.vaultContains(activeRootURL, destinationURL) {
                projectVaultSnapshotsByPath[Self.vaultCanonicalPath(destinationURL)] = snapshot
            }
        }
        if let transfer = snapshot.transfer {
            projectVaultSnapshotsByPath[Self.vaultCanonicalPath(transfer.sourceURL)] = snapshot
            let terminalStates: Set<VaultTransferState> = [
                .archiveVerified, .archivedLocal, .archivedOnlineOnly,
            ]
            if !terminalStates.contains(transfer.state)
                || projectVaultPresentationContext?.generationReviewResolver?
                    .isBoundGenerationPath(
                        transfer.destinationURL,
                        projectID: transfer.projectID,
                        transferID: transfer.id
                    ) == true {
                projectVaultSnapshotsByPath[Self.vaultCanonicalPath(transfer.destinationURL)] = snapshot
            }
        }
    }

    private func archivedOnlySnapshots(from snapshots: [ProjectVaultRuntimeSnapshot]) -> [ProjectVaultRuntimeSnapshot] {
        guard let generationResolver = projectVaultPresentationContext?.generationReviewResolver else {
            return []
        }
        return snapshots.filter { snapshot in
            guard let transfer = snapshot.transfer else { return false }
            let isVerifiedTerminal = [
                VaultTransferState.archiveVerified,
                .archivedLocal,
                .archivedOnlineOnly,
            ].contains(transfer.state)
            let isDestructiveRecoveryHandle = transfer.state == .recoveryRequired
                && (transfer.error?.origin == .removingActiveCopy
                    || transfer.error?.origin == .evictingProviderCache)
            guard (isVerifiedTerminal || isDestructiveRecoveryHandle),
                  generationResolver.isBoundGenerationPath(
                    transfer.destinationURL,
                    projectID: transfer.projectID,
                    transferID: transfer.id
                  ) else {
                return false
            }
            // The Active copy is the deciding signal. The archive destination may be
            // an online-only Dropbox generation with no materialized local directory;
            // the verified transfer record is still enough to show and restore it.
            return !FileManager.default.fileExists(atPath: transfer.sourceURL.path)
        }
    }

    func rebuildProjectVaultCatalog() {
        let projected = projectVaultCatalog(from: scannedSongs)
        guard projected.scannedSongs != scannedSongs || projected.visibleSongs != songs else { return }
        mutateCatalog {
            scannedSongs = projected.scannedSongs
            songs = projected.visibleSongs
        }
    }

    func projectVaultCatalog(from baselineSongs: [Song]) -> (scannedSongs: [Song], visibleSongs: [Song]) {
        let archivedSnapshots = archivedOnlySnapshots(from: projectVaultSnapshots)
        let archivedDestinationPaths = Set(archivedSnapshots.compactMap { snapshot in
            snapshot.transfer.map { Self.vaultCanonicalPath($0.destinationURL) }
        })
        let archivedSourcePaths = Set(archivedSnapshots.compactMap { snapshot in
            snapshot.transfer.map { Self.vaultCanonicalPath($0.sourceURL) }
        })

        // Old cache snapshots may contain an archive projection from a previous app
        // version. Remove those paths from the scan baseline once the vault snapshot
        // is known, even when the user keeps archived projects hidden.
        let cleanScannedSongs = baselineSongs.filter { song in
            let path = Self.vaultCanonicalPath(song.folderPath)
            return !archivedDestinationPaths.contains(path) && !archivedSourcePaths.contains(path)
        }
        var archivedSongs: [Song] = []
        if showArchivedProjects, !archivedSnapshots.isEmpty {
            var metadata = Dictionary(uniqueKeysWithValues: baselineSongs.map {
                ($0.id, SongUserMetadata.from(song: $0))
            })
            do {
                metadata.merge(try catalog.songMetadataStore?.loadAll() ?? [:]) { _, persisted in persisted }
            } catch {
                recordPersistenceWarning("Archived project metadata could not be loaded: \(error.localizedDescription)")
            }
            archivedSongs = archivedSnapshots.compactMap { snapshot in
                let sourceID = snapshot.transfer?.sourceURL.standardizedFileURL.path
                return makeArchivedSong(from: snapshot, metadata: sourceID.flatMap { metadata[$0] })
            }
        }
        let visibleSongs = SongCatalogDeduplicator.uniqueByID(cleanScannedSongs + archivedSongs)
        return (cleanScannedSongs, visibleSongs)
    }

    private func makeArchivedSong(from snapshot: ProjectVaultRuntimeSnapshot, metadata: SongUserMetadata?) -> Song? {
        guard let transfer = snapshot.transfer else { return nil }
        let destination = transfer.destinationURL.standardizedFileURL
        let detector = ProjectVersionDetector()
        let hasMaterializedDestination = FileManager.default.fileExists(atPath: destination.path)
        let versions = hasMaterializedDestination
            ? ((try? detector.detectVersions(in: destination)) ?? [])
            : []
        let title = snapshot.record.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return Song(
            folderPath: destination,
            originalFolderName: transfer.sourceURL.lastPathComponent,
            displayTitle: title.isEmpty ? transfer.sourceURL.lastPathComponent : title,
            projectVersions: versions,
            latestCPR: detector.latestCPR(from: versions),
            virtualTitle: metadata?.virtualTitle,
            aliases: metadata?.aliases ?? [],
            appNote: metadata?.appNote,
            collaboratorIDs: metadata?.collaboratorIDs ?? [],
            collaboratorNames: collaborators.filter { metadata?.collaboratorIDs.contains($0.id) == true }.map(\.displayName),
            workflowStatus: metadata.map(\.workflowStatus) ?? snapshot.record.workflowState,
            isIgnored: metadata?.isIgnored ?? false
        )
    }

    private static func vaultCanonicalPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
        for alias in ["/private/var", "/private/tmp"] {
            if path == alias { return String(alias.dropFirst("/private".count)) }
            if path.hasPrefix(alias + "/") { return String(path.dropFirst("/private".count)) }
        }
        return path
    }

    private static func vaultContains(_ root: URL, _ candidate: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count >= rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
