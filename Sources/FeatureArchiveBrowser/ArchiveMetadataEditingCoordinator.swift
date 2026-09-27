import AppCore
import Combine
import Foundation
import NikoMusicCore

/// Required immutable integration contract for song-metadata editing.
///
/// All callbacks are supplied together at initialization and never rebound.
/// Snapshot getters return an optional snapshot: `nil` means the host is gone
/// and snapshot-dependent edits/persistence no-op (no default generation). Gate
/// closures (`isVaultBlocked`, `canMutateStatus`, `canArchive`) always return
/// a decision; the view-model factory maps a vanished host to the refusing
/// value (blocked / false). Void callbacks no-op when the host is gone. This
/// owner never retains the view model; every capture is weak.
struct ArchiveMetadataEditingHost {
    let currentSongs: @MainActor () -> [Song]?
    let currentScannedSongs: @MainActor () -> [Song]?
    let currentCollaborators: @MainActor () -> [Collaborator]?
    let currentRoots: @MainActor () -> [URL]?
    let currentGeneration: @MainActor () -> UInt64?
    let currentScanDate: @MainActor () -> Date?
    let isVaultBlocked: @MainActor (Song) -> Bool
    let canMutateStatus: @MainActor (Song) -> Bool
    let canArchive: @MainActor (Song) -> Bool
    let requestDoneArchive: @MainActor (Song) -> Void
    let revokeDoneWork: @MainActor (String) -> Void
    let applyReplacement: @MainActor (Song) -> Void
    let currentPersistenceWarning: @MainActor () -> String?
    let setPersistenceWarningDirect: @MainActor (String?) -> Void
    let reportWarning: @MainActor (String) -> Void
    let reportStatus: @MainActor (String) -> Void
    let reportVaultStatus: @MainActor (String) -> Void
}

/// Single MainActor owner for song-metadata mutation, gating, persistence
/// ordering, notes/status undo, repair IDs, and delayed index persistence.
///
/// `ArchiveCatalogCoordinator` stays the lower-level merge/store owner; this
/// coordinator owns the edit-level ordering on top of it. `ArchiveBrowserViewModel`
/// keeps composition (songs/scanned baseline, collaborators, roots, selection,
/// preview invalidation, Vault Done capture/revoke, queue) and injects the
/// narrow weak host once at creation (see the lazy owner factory in
/// `ArchiveBrowserViewModel`). This owner never retains the view model.
@MainActor
final class ArchiveMetadataEditingCoordinator: ObservableObject {
    // MARK: - Lower-level catalog (intact, shared integrity)

    let catalog: ArchiveCatalogCoordinator

    // MARK: - Owned undo state

    /// Owned fallback stack. Never created per-window; the window manager is
    /// bound weakly while the pane is active.
    let ownedUndoManager = UndoManager()
    private(set) var injectedUndoManager: UndoManager?
    weak private(set) var boundWindowUndoManager: UndoManager?
    let undoTarget = ArchiveWorkflowUndoTarget()

    // MARK: - Owned repair + index lifecycle

    @Published private(set) var repairSongIDs: Set<String> = []
    private(set) var indexPersistTask: Task<Void, Never>?

    // MARK: - Required immutable host (weak captures, set once)

    private let host: ArchiveMetadataEditingHost

    init(catalog: ArchiveCatalogCoordinator, host: ArchiveMetadataEditingHost) {
        self.catalog = catalog
        self.host = host
        undoTarget.coordinator = self
    }

    deinit {
        indexPersistTask?.cancel()
    }

    // MARK: - Undo managers (owned/injected/weak window-bound)

    /// Manager for fresh edits: injected test precedence, native window
    /// primary, owned fallback. Never creates a manager.
    var effectiveUndoManager: UndoManager? {
        injectedUndoManager ?? boundWindowUndoManager ?? ownedUndoManager
    }

    /// Manager currently driving an undo/redo, so the inverse re-registers on
    /// the same stack that drove it. Falls back to `effectiveUndoManager` for
    /// fresh edits.
    var drivingUndoManager: UndoManager? {
        let candidates: [UndoManager?] = [
            injectedUndoManager,
            boundWindowUndoManager,
            ownedUndoManager,
        ]
        for candidate in candidates {
            if let manager = candidate, manager.isUndoing || manager.isRedoing {
                return manager
            }
        }
        return effectiveUndoManager
    }

    /// Intentional test injection. Replaces the writable-storage alias;
    /// production uses the window binding or the owned fallback.
    func bindInjectedUndoManager(_ manager: UndoManager?) {
        injectedUndoManager = manager
    }

    /// Primary native route: publish the window's EXISTING undo manager while
    /// the pane is active. Never creates a manager. Scrub removes only this
    /// owner's actions, leaving unrelated window actions intact.
    func bindWindowUndoManager(_ manager: UndoManager?) {
        if boundWindowUndoManager === manager { return }
        if let old = boundWindowUndoManager {
            old.removeAllActions(withTarget: undoTarget)
        }
        boundWindowUndoManager = manager
    }

    func unbindWindowUndoManager() {
        if let old = boundWindowUndoManager {
            old.removeAllActions(withTarget: undoTarget)
        }
        boundWindowUndoManager = nil
    }

    // MARK: - Notes edits (normalized once, single atomic commit)

    func updateVirtualTitle(for song: Song, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.virtualTitle = trimmed.isEmpty ? nil : trimmed
        }
    }

    func updateAppNote(for song: Song, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.appNote = trimmed.isEmpty ? nil : trimmed
        }
    }

    func updateAliases(for song: Song, aliasesText: String) {
        let aliases = aliasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.aliases = aliases
        }
    }

    /// Single-commit title/aliases/note edit. Normalizes exactly like the
    /// single-field updaters, then goes through the one apply/commit path so
    /// a three-field save persists/replaces/recomputes once. Unrelated stored
    /// fields are preserved by the merge.
    func applySongNotes(
        for song: Song,
        virtualTitle: String,
        aliasesText: String,
        appNote: String
    ) {
        let trimmedTitle = virtualTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = appNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = aliasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.virtualTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
            metadata.aliases = aliases
            metadata.appNote = trimmedNote.isEmpty ? nil : trimmedNote
        }
    }

    func flushMetadataDrafts(
        songID: String,
        virtualTitle: String,
        aliases: String,
        appNote: String
    ) {
        guard let songs = host.currentSongs(),
              let song = songs.first(where: { $0.id == songID }) else { return }
        applySongNotes(for: song, virtualTitle: virtualTitle, aliasesText: aliases, appNote: appNote)
    }

    func statusHistory(for song: Song, limit: Int = 5) -> [WorkflowStatusChange] {
        guard let reader = catalog.songMetadataStore as? WorkflowStatusHistoryReading else {
            return []
        }
        let all = (try? reader.statusHistory(forSongID: song.id)) ?? []
        return Array(all.suffix(limit))
    }

    func registerMetadataUndo(
        songID: String,
        previousVirtualTitle: String?,
        previousAliases: [String],
        previousAppNote: String?,
        actionName: String = "Edit Song Notes"
    ) {
        guard let undoManager = drivingUndoManager else { return }
        undoManager.registerUndo(withTarget: undoTarget) { target in
            MainActor.assumeIsolated {
                target.undoMetadata(
                    songID: songID,
                    previousVirtualTitle: previousVirtualTitle,
                    previousAliases: previousAliases,
                    previousAppNote: previousAppNote,
                    actionName: actionName
                )
            }
        }
        if !undoManager.isUndoing, !undoManager.isRedoing {
            undoManager.setActionName(actionName)
        }
    }

    func undoMetadata(
        songID: String,
        previousVirtualTitle: String?,
        previousAliases: [String],
        previousAppNote: String?,
        actionName: String = "Edit Song Notes"
    ) {
        guard let songs = host.currentSongs(),
              let song = songs.first(where: { $0.id == songID }) else { return }
        let currentTitle = song.virtualTitle
        let currentAliases = song.aliases
        let currentNote = song.appNote
        applySongNotes(
            for: song,
            virtualTitle: previousVirtualTitle ?? "",
            aliasesText: previousAliases.joined(separator: ", "),
            appNote: previousAppNote ?? ""
        )
        registerMetadataUndo(
            songID: songID,
            previousVirtualTitle: currentTitle,
            previousAliases: currentAliases,
            previousAppNote: currentNote,
            actionName: actionName
        )
    }

    // MARK: - Workflow status (ordinary commits; Done capture stays in VM/Vault)

    func applyWorkflowStatus(
        _ status: ProjectWorkflowStatus?,
        for song: Song,
        registerUndo: Bool = true
    ) {
        updateWorkflowStatus(for: song, status: status, registerUndo: registerUndo)
    }

    func updateWorkflowStatus(
        for song: Song,
        status: ProjectWorkflowStatus?,
        registerUndo: Bool = true
    ) {
        guard host.canMutateStatus(song) else { return }
        guard let songs = host.currentSongs() else { return }
        let previous = songs.first(where: { $0.id == song.id })?.workflowStatus ?? song.workflowStatus
        guard previous != status else { return }
        if status == .done {
            if host.canArchive(song) {
                host.requestDoneArchive(song)
                return
            }
        }
        commitWorkflowStatus(status, for: song)
        if previous == .done, status != .done {
            host.revokeDoneWork(song.id)
        }
        if registerUndo {
            registerWorkflowStatusUndo(
                songID: song.id,
                previousStatus: previous,
                actionName: "Change Workflow Status"
            )
        }
    }

    func commitWorkflowStatus(_ status: ProjectWorkflowStatus?, for song: Song) {
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.workflowStatus = status
        }
    }

    func registerWorkflowStatusUndo(
        songID: String,
        previousStatus: ProjectWorkflowStatus?,
        actionName: String
    ) {
        guard let undoManager = drivingUndoManager else { return }
        undoManager.registerUndo(withTarget: undoTarget) { target in
            MainActor.assumeIsolated {
                target.undoWorkflowStatus(
                    songID: songID,
                    previousStatus: previousStatus,
                    actionName: actionName
                )
            }
        }
        if !undoManager.isUndoing, !undoManager.isRedoing {
            undoManager.setActionName(actionName)
        }
    }

    func undoWorkflowStatus(
        songID: String,
        previousStatus: ProjectWorkflowStatus?,
        actionName: String
    ) {
        guard let songs = host.currentSongs(),
              let song = songs.first(where: { $0.id == songID }) else { return }
        let currentStatus = song.workflowStatus
        let leavingDone = currentStatus == .done && previousStatus != .done
        commitWorkflowStatus(previousStatus, for: song)
        if leavingDone {
            host.revokeDoneWork(songID)
            if let live = host.currentSongs()?.first(where: { $0.id == songID }),
               !FileManager.default.fileExists(atPath: live.folderPath.path) {
                host.reportVaultStatus("Undo restored the workflow status. The Active Projects folder was already archived and removed; use Restore & Open to review the verified archive.")
            }
        }
        registerWorkflowStatusUndo(
            songID: songID,
            previousStatus: currentStatus,
            actionName: actionName
        )
    }

    // MARK: - Preview / CPR / hidden / collaborators (core merge; invalidation stays in VM)

    func assignCollaborators(to song: Song, collaboratorIDs: [String]) {
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.collaboratorIDs = collaboratorIDs
        }
    }

    // MARK: - Core gate / merge / authoritative persist / replace

    func applyMetadataMerge(
        for song: Song,
        rankingRefresh: ArchiveSongMetadataEditor.RankingRefresh = .none,
        mutate: (inout SongUserMetadata, inout Song) -> Void
    ) {
        if host.isVaultBlocked(song) { return }
        if let blockWarning = catalog.metadataEditBlockWarning(for: song.id) {
            host.reportWarning(blockWarning)
            return
        }
        guard let songs = host.currentSongs() else { return }
        guard let merged = ArchiveSongMetadataEditor.mergedSongAfterEdit(
            for: song,
            in: songs,
            collaborators: host.currentCollaborators() ?? [],
            rankingRefresh: rankingRefresh,
            mutate: mutate
        ) else { return }
        commitSongMetadataUpdate(merged)
    }

    private func commitSongMetadataUpdate(_ updated: Song) {
        if let blockWarning = catalog.metadataEditBlockWarning(for: updated.id) {
            host.reportWarning(blockWarning)
            syncRepairState()
            return
        }
        let warning = catalog.persistUserMetadata(for: [updated])
        if let warning, catalog.metadataEditBlockWarning(for: updated.id) != nil {
            host.reportWarning(warning)
            syncRepairState()
            return
        }
        host.applyReplacement(updated)
        if let warning {
            host.reportWarning(warning)
        }
        scheduleDebouncedIndexPersist()
    }

    // MARK: - Delayed index persistence (serialized, live snapshot, generation gate)

    func scheduleDebouncedIndexPersist() {
        scheduleIndexPersist(afterNanoseconds: 500_000_000)
    }

    func scheduleIndexPersist(afterNanoseconds delay: UInt64) {
        guard let roots = host.currentRoots(), !roots.isEmpty else { return }
        guard let generation = host.currentGeneration() else { return }
        let previous = indexPersistTask
        previous?.cancel()
        indexPersistTask = Task { @MainActor [weak self] in
            _ = await previous?.value
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard let self, !Task.isCancelled else { return }
            guard let liveRoots = self.host.currentRoots(), !liveRoots.isEmpty,
                  self.host.currentGeneration() == generation else { return }
            guard let liveSongs = self.host.currentScannedSongs() else { return }
            let scannedAt = self.host.currentScanDate() ?? Date()
            if let warning = await self.catalog.persistCachedIndexDetached(
                roots: liveRoots,
                songs: liveSongs,
                scannedAt: scannedAt
            ) {
                self.host.reportWarning(warning)
            }
        }
    }

    /// Cancels the pending delayed write but RETAINS the handle as the
    /// predecessor for the next schedule. The detached cache write itself is
    /// not cancellable mid-flight, so a newer root snapshot must still await
    /// the held older write; nil-ing here would let the newer snapshot land
    /// first and then get overwritten by the stale write.
    func cancelPendingIndexPersist() {
        indexPersistTask?.cancel()
    }

    // MARK: - Repair (exact rows, integrity warning, no whole-store per-edit load)

    func syncRepairState() {
        guard host.currentSongs() != nil || host.currentScannedSongs() != nil else { return }
        let scanned = Set((host.currentScannedSongs() ?? []).map(\.id))
        let visible = Set((host.currentSongs() ?? []).map(\.id))
        let present = scanned.union(visible)
        let ids = catalog.corruptSongIDs().intersection(present)
        if ids != repairSongIDs {
            repairSongIDs = ids
        }
    }

    func clearRepairStateForRootChange() {
        if !repairSongIDs.isEmpty {
            repairSongIDs = []
        }
    }

    func clearForRootChange() {
        cancelPendingIndexPersist()
        clearRepairStateForRootChange()
    }

    func repairSongMetadata(songIDs: [String]) {
        guard !songIDs.isEmpty else { return }
        let result = catalog.repairSongMetadata(songIDs: songIDs)
        let collaboratorsByID = Dictionary(uniqueKeysWithValues: (host.currentCollaborators() ?? []).map { ($0.id, $0) })
        var repairedNames: [String] = []
        for songID in songIDs {
            guard let metadata = result.reloaded[songID] else { continue }
            let current = host.currentSongs()?.first(where: { $0.id == songID })
                ?? host.currentScannedSongs()?.first(where: { $0.id == songID })
            guard let current else { continue }
            let merged = ArchiveMetadataMerger.merge(
                scanned: current,
                metadata: metadata,
                collaboratorsByID: collaboratorsByID
            )
            host.applyReplacement(merged)
            repairedNames.append(SongMetadataIntegrityCopy.name(of: merged))
        }
        syncRepairState()
        if let current = host.currentPersistenceWarning(), SongMetadataIntegrityCopy.isIntegrityWarning(current) {
            host.setPersistenceWarningDirect(catalog.metadataIntegrityWarning())
        }
        var parts: [String] = []
        if !repairedNames.isEmpty {
            parts.append(SongMetadataIntegrityCopy.repaired(names: repairedNames, cleared: result.clearedLists))
        }
        if !result.failedSongIDs.isEmpty {
            let failedNames = result.failedSongIDs.map { id in
                host.currentSongs()?.first(where: { $0.id == id }).map(SongMetadataIntegrityCopy.name(of:))
                    ?? SongMetadataIntegrityCopy.folderName(for: id)
            }
            parts.append(SongMetadataIntegrityCopy.repairFailed(names: failedNames))
        }
        host.reportStatus(parts.joined(separator: " "))
        if !repairedNames.isEmpty {
            scheduleIndexPersist(afterNanoseconds: 0)
        }
    }
}
