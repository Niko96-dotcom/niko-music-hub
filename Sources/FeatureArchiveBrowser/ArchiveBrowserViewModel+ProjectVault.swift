import AppCore
import Foundation
import NikoMusicCore

/// The small, immutable subset of settings that determines Project Vault card
/// state. It is loaded once while refreshing the presentation cache, never from
/// a SwiftUI card render.
struct ProjectVaultPresentationContext: Equatable {
    let activeRoot: StoredMusicRoot?
    let keepLocalProjectIDs: Set<String>

    init?(settings: AppSettings) {
        guard settings.vault.isEnabled else { return nil }
        activeRoot = settings.musicRoots.first { $0.id == settings.vault.activeRootID }
        keepLocalProjectIDs = settings.vault.keepLocalProjectIDs
    }
}

/// Archive-only Project Vault cards are restore targets, not workflow inputs.
/// Keeping this decision shared between card surfaces and the view model prevents
/// drag/drop or menu affordances from bypassing the same safety boundary.
enum ProjectVaultCardWorkflowPolicy {
    static func allowsWorkflowMutation(for presentation: ProjectVaultCardPresentation?) -> Bool {
        presentation?.state != .archived
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
                Task { await scan() }
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

    func canMutateWorkflowStatus(for song: Song) -> Bool {
        ProjectVaultCardWorkflowPolicy.allowsWorkflowMutation(
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
            return ProjectVaultCardPresentation(record: record, transferState: transferState)
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
              projectVaultPresentation(for: song)?.state != .archived else { return false }
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
            setStatusMessage("Keep Local could not be saved. No project files were changed.")
        }
    }

    func archiveInProjectVault(_ song: Song, trigger: ProjectVaultArchiveTrigger = .manual) {
        guard let projectVaultRuntime, !projectVaultBusySongIDs.contains(song.id) else { return }
        projectVaultBusySongIDs.insert(song.id)
        setStatusMessage(trigger == .workflowDone ? "Done — checking Project Vault safety…" : "Archiving and verifying a Project Vault copy…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.projectVaultBusySongIDs.remove(song.id) }
            do {
                let snapshot = try await projectVaultRuntime.archive(song: song, trigger: trigger)
                self.projectVaultRetryTasks.removeValue(forKey: song.id)?.cancel()
                self.cacheProjectVaultSnapshot(snapshot)
                self.rebuildProjectVaultPresentationCache()
                await self.refreshProjectVaultSnapshots()
                let activeRetained = FileManager.default.fileExists(atPath: song.folderPath.path)
                self.setStatusMessage(activeRetained
                    ? "Archived and verified. The Active copy was kept."
                    : "Done and archived. The verified project is ready to restore when needed.")
            } catch let error as ProjectVaultRuntimeError where trigger == .workflowDone {
                self.setStatusMessage("Marked Done. \(error.localizedDescription)")
                self.diagnostics.log(.warning, "Done auto-archive postponed: \(error)")
                self.scheduleDoneArchiveRetry(for: song)
            } catch {
                self.setStatusMessage("Project Vault could not archive this project: \(error.localizedDescription). No source files were changed.")
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
        case .review:
            setStatusMessage(presentation.explanation)
        }
    }

    func refreshProjectVaultSnapshots() async {
        guard let projectVaultRuntime else { return }
        do {
            let snapshots = try await projectVaultRuntime.snapshots()
            projectVaultSnapshots = snapshots
            projectVaultSnapshotsByPath.removeAll()
            snapshots.forEach(cacheProjectVaultSnapshot)
            archivedProjectCount = archivedOnlySnapshots(from: snapshots).count
            rebuildProjectVaultCatalog()
            rebuildProjectVaultPresentationCache()
            enqueueDoneVaultProjectsIfNeeded()
        } catch ProjectVaultRuntimeError.unavailable {
            projectVaultSnapshots = []
            projectVaultSnapshotsByPath.removeAll()
            archivedProjectCount = 0
            rebuildProjectVaultCatalog()
            rebuildProjectVaultPresentationCache()
        } catch {
            diagnostics.log(.error, "Project Vault state refresh failed: \(error)")
        }
    }

    private func enqueueDoneVaultProjectsIfNeeded() {
        for song in songs where song.workflowStatus == .done {
            let transfer = projectVaultSnapshot(for: song)?.transfer
            let isAlreadyArchived = transfer.map {
                [.archiveVerified, .archivedLocal, .archivedOnlineOnly].contains($0.state)
            } ?? false
            if !isAlreadyArchived, !projectVaultBusySongIDs.contains(song.id) {
                archiveInProjectVault(song, trigger: .workflowDone)
            }
        }
    }

    private func scheduleDoneArchiveRetry(for song: Song) {
        guard projectVaultRetryTasks[song.id] == nil else { return }
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
            setStatusMessage("Restore is unavailable because no verified Project Vault generation was found.")
            return
        }
        guard !projectVaultBusySongIDs.contains(song.id) else { return }
        projectVaultBusySongIDs.insert(song.id)
        setStatusMessage("Restoring the verified project into Active Projects…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.projectVaultBusySongIDs.remove(song.id) }
            do {
                _ = try await runtime.restoreAndOpen(snapshot: snapshot)
                await self.refreshProjectVaultSnapshots()
                await self.scan()
                self.setStatusMessage("Restored, verified, and opened in Cubase.")
            } catch {
                self.setStatusMessage("Restore stopped safely: \(error.localizedDescription). The archive copy was kept.")
                self.diagnostics.log(.error, "Project Vault restore failed: \(error)")
            }
        }
    }

    private func projectVaultSnapshot(for song: Song) -> ProjectVaultRuntimeSnapshot? {
        projectVaultSnapshotsByPath[Self.vaultCanonicalPath(song.folderPath)]
    }

    private func cacheProjectVaultSnapshot(_ snapshot: ProjectVaultRuntimeSnapshot) {
        if let transfer = snapshot.transfer {
            projectVaultSnapshotsByPath[Self.vaultCanonicalPath(transfer.sourceURL)] = snapshot
            projectVaultSnapshotsByPath[Self.vaultCanonicalPath(transfer.destinationURL)] = snapshot
        }
    }

    private func archivedOnlySnapshots(from snapshots: [ProjectVaultRuntimeSnapshot]) -> [ProjectVaultRuntimeSnapshot] {
        snapshots.filter { snapshot in
            guard let transfer = snapshot.transfer,
                  [.archiveVerified, .archivedLocal, .archivedOnlineOnly].contains(transfer.state) else {
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
        let archivedSongs = showArchivedProjects
            ? archivedSnapshots.compactMap(makeArchivedSong)
            : []
        let visibleSongs = SongCatalogDeduplicator.uniqueByID(cleanScannedSongs + archivedSongs)
        return (cleanScannedSongs, visibleSongs)
    }

    private func makeArchivedSong(from snapshot: ProjectVaultRuntimeSnapshot) -> Song? {
        guard let transfer = snapshot.transfer else { return nil }
        let destination = transfer.destinationURL.standardizedFileURL
        let detector = CPRVersionDetector()
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
            workflowStatus: snapshot.record.workflowState
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
