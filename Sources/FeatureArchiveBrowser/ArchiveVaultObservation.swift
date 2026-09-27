import AppCore
import Combine
import Foundation
import NikoMusicCore

/// Single MainActor owner for Vault observation/presentation state.
///
/// Owns the prepared settings context, provider health, the runtime snapshot
/// list and its canonical path index, the immutable card cache, the archived
/// count, the archive-only catalog projection inputs, and the
/// automatic-recovery timer task/deadline/backoff lifecycle.
///
/// All mutable storage is `private(set)` with intentional input/operation
/// methods. Derivation, gating, and timer lifecycle live here with the
/// storage; `ArchiveBrowserViewModel` keeps composition (current
/// songs/scanned baseline, collaborators, user-visible status and
/// enqueue-Done followups), runtime operation execution, confirmations/auth,
/// scan/root handling, and settings-change orchestration. The view model
/// bridges `objectWillChange` through a weak subscription so existing views
/// keep reading read-only peers with no UI edits. This owner never retains
/// the view model; recovery callbacks are narrow and weak.
@MainActor
final class ArchiveVaultObservation: ObservableObject {
    // MARK: - Owned state (single source of truth)

    /// Prepared settings context. Replaced only at the explicit
    /// settings boundary (`refreshContext(settings:songs:)`); the render
    /// path never touches `SettingsStore`.
    private(set) var context: ProjectVaultPresentationContext?
    /// Sidebar provider status. Rides the same settings boundary as the card
    /// map; views read the cached value.
    private(set) var health = ProjectVaultHealth(
        providerStatus: .notConfigured,
        lastSuccessfulVerificationAt: nil,
        hasIndependentBackup: false
    )
    /// Latest runtime snapshot list. Retained separately from the path lookup
    /// map so changing archived visibility rebuilds the catalog without
    /// another scan or round trip.
    private(set) var snapshots: [ProjectVaultRuntimeSnapshot] = []
    /// Canonical path index for O(1) card lookups. Rebuilt with the snapshot
    /// list; single-live updates go through `cache(_:)`.
    private(set) var snapshotsByPath: [String: ProjectVaultRuntimeSnapshot] = [:]
    /// Immutable per-song card state. `presentation(for:)` is a dictionary
    /// lookup so list and board re-renders stay main-thread cheap.
    private(set) var presentationsBySongID: [String: ProjectVaultCardPresentation] = [:]
    /// Archive-only generations for the sidebar/board toggle.
    private(set) var archivedCount = 0
    /// Automatic-recovery timer deadline. Plain observation state: tests poll
    /// it; changes do not publish (matches the former plain view-model var).
    private(set) var recoveryDeadline: Date?
    private var recoveryTask: Task<Void, Never>?
    /// Local backoff anchor so an unchanged overdue record does not spin.
    private(set) var lastRecoveryAttemptAt: Date?

    init() {}

    /// `recoveryTask` is a Sendable task handle and `Task.cancel()` is
    /// thread-safe, so `deinit` cancels it directly with no actor-isolated
    /// call (same pattern as `ProjectVaultOperationCoordinator.deinit`).
    deinit {
        recoveryTask?.cancel()
    }

    // MARK: - Settings / context / cards

    /// Loads the narrow settings context at an explicit settings boundary,
    /// then rebuilds the card map. The render path itself never calls
    /// `SettingsStore`. `settings` is the already-loaded snapshot (nil when
    /// the load failed); `songs` is the current catalog for card prebuild.
    /// A health change always publishes, even for a silent refresh, so the
    /// sidebar provider status never goes stale mid-transfer. Context-only or
    /// cards-only changes stay silent when `notifyWhenChanged` is false.
    /// Publishes at most once per call. Returns true when context, health,
    /// or cards changed.
    @discardableResult
    func refreshContext(
        settings: AppSettings?,
        songs: [Song],
        notifyWhenChanged: Bool = true
    ) -> Bool {
        let nextContext = settings.flatMap(ProjectVaultPresentationContext.init(settings:))
        let contextChanged = nextContext != context
        context = nextContext
        var healthChanged = false
        if let settings {
            let nextHealth = ProjectVaultHealthEvaluator().evaluate(settings: settings)
            if nextHealth != health {
                health = nextHealth
                healthChanged = true
            }
        }
        let cardsChanged = rebuildCards(for: songs, notifyWhenChanged: false)
        let changed = contextChanged || healthChanged || cardsChanged
        if healthChanged || (changed && notifyWhenChanged) {
            objectWillChange.send()
        }
        return changed
    }

    /// Rebuilds immutable card data at a catalog or snapshot boundary.
    /// Uses the already-prepared context; never reads settings. Returns true
    /// when the map changed.
    @discardableResult
    func rebuildCards(for songs: [Song], notifyWhenChanged: Bool = true) -> Bool {
        let currentContext = context
        var nextPresentations: [String: ProjectVaultCardPresentation] = [:]
        nextPresentations.reserveCapacity(songs.count)
        if let currentContext {
            for song in songs {
                if let presentation = makePresentation(for: song, context: currentContext) {
                    nextPresentations[song.id] = presentation
                }
            }
        }
        guard nextPresentations != presentationsBySongID else { return false }
        presentationsBySongID = nextPresentations
        if notifyWhenChanged {
            objectWillChange.send()
        }
        return true
    }

    // MARK: - Snapshots / index / count

    /// Stages list/index/count without touching cards. Normal refresh stages,
    /// rebuilds the catalog, then rebuilds cards once for the final songs.
    /// Full-refresh path: also updates the archived count. Returns true when
    /// the list or count changed.
    @discardableResult
    func stageSnapshots(_ nextSnapshots: [ProjectVaultRuntimeSnapshot]) -> Bool {
        let listChanged = storeSnapshotsAndRebuildIndex(nextSnapshots)
        let nextCount = archivedOnlySnapshots(from: nextSnapshots).count
        let countChanged = nextCount != archivedCount
        if countChanged {
            archivedCount = nextCount
        }
        return listChanged || countChanged
    }

    /// Atomic poller update. No-op when the list is unchanged (no rebuild, no
    /// publish); otherwise updates the list, rebuilds the path index, rebuilds
    /// cards once, and publishes once. Leaves `archivedCount` unchanged; the
    /// count changes only in the full-refresh path (`stageSnapshots`).
    @discardableResult
    func applyPolledSnapshots(
        _ nextSnapshots: [ProjectVaultRuntimeSnapshot],
        songs: [Song]
    ) -> Bool {
        guard nextSnapshots != snapshots else { return false }
        _ = storeSnapshotsAndRebuildIndex(nextSnapshots)
        _ = rebuildCards(for: songs, notifyWhenChanged: false)
        objectWillChange.send()
        return true
    }

    /// Stores the snapshot list and rebuilds the path index. Shared by the
    /// full-refresh and poll paths; the archived count stays with the
    /// full-refresh path. Returns true when the list changed.
    private func storeSnapshotsAndRebuildIndex(_ nextSnapshots: [ProjectVaultRuntimeSnapshot]) -> Bool {
        let listChanged = nextSnapshots != snapshots
        snapshots = nextSnapshots
        rebuildPathIndex()
        return listChanged
    }

    /// Root-change path (`clearRootBoundArchiveState`): clears the list,
    /// index, and count. Cards are rebuilt by the subsequent `songs = []`
    /// assignment's prebuild; no card work here to avoid double rebuild.
    func clearForRootChange(notifyWhenChanged: Bool = true) {
        let hadSnapshots = !snapshots.isEmpty
        let hadIndex = !snapshotsByPath.isEmpty
        let hadCount = archivedCount != 0
        snapshots = []
        snapshotsByPath.removeAll()
        archivedCount = 0
        if notifyWhenChanged, hadSnapshots || hadIndex || hadCount {
            objectWillChange.send()
        }
    }

    /// Caches one live snapshot into the path index (linked, restore
    /// destination, source, and bound destination keys). Index-only; callers
    /// rebuild cards explicitly so single-live updates stay coalesced.
    func cache(_ snapshot: ProjectVaultRuntimeSnapshot) {
        if let linked = linkedArchive(for: snapshot) {
            snapshotsByPath[Self.vaultCanonicalPath(linked.url)] = snapshot
        }
        if let restore = snapshot.restore,
           restore.projectID == snapshot.record.id,
           restore.completedAt == nil,
           let activeRoot = context?.activeRoot {
            let activeRootURL = activeRoot.fallbackURL
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let destinationURL = restore.destinationURL
                .standardizedFileURL
                .resolvingSymlinksInPath()
            if destinationURL != activeRootURL,
               Self.vaultContains(activeRootURL, destinationURL) {
                snapshotsByPath[Self.vaultCanonicalPath(destinationURL)] = snapshot
            }
        }
        if let transfer = snapshot.transfer {
            snapshotsByPath[Self.vaultCanonicalPath(transfer.sourceURL)] = snapshot
            let terminalStates: Set<VaultTransferState> = [
                .archiveVerified, .archivedLocal, .archivedOnlineOnly,
            ]
            if !terminalStates.contains(transfer.state)
                || context?.generationReviewResolver?
                    .isBoundGenerationPath(
                        transfer.destinationURL,
                        projectID: transfer.projectID,
                        transferID: transfer.id
                    ) == true {
                snapshotsByPath[Self.vaultCanonicalPath(transfer.destinationURL)] = snapshot
            }
        }
    }

    /// Rebuilds the full path index from `snapshots`. Uses the current
    /// context for linked/restore/bound gating.
    private func rebuildPathIndex() {
        snapshotsByPath.removeAll()
        for snapshot in snapshots {
            cache(snapshot)
        }
    }

    // MARK: - Lookups (O(1), no settings reads)

    func presentation(for song: Song) -> ProjectVaultCardPresentation? {
        presentationsBySongID[song.id]
    }

    func snapshot(for song: Song) -> ProjectVaultRuntimeSnapshot? {
        snapshotsByPath[Self.vaultCanonicalPath(song.folderPath)]
    }

    func linkedArchive(for snapshot: ProjectVaultRuntimeSnapshot) -> ProjectVaultLinkedArchive? {
        guard snapshot.transfer == nil,
              let linked = snapshot.linkedArchive, linked.location.availability != .missing,
              snapshot.record.locations.contains(linked.location),
              let root = context?.archiveRoot,
              let resolved = ProjectArchiveLocationResolver(rootID: root.id, rootURL: root.fallbackURL).resolve(linked.location),
              Self.vaultCanonicalPath(resolved) == Self.vaultCanonicalPath(linked.url) else { return nil }
        return linked
    }

    func archivedOnlySnapshots(from snapshots: [ProjectVaultRuntimeSnapshot]) -> [ProjectVaultRuntimeSnapshot] {
        guard let generationResolver = context?.generationReviewResolver else {
            return []
        }
        return snapshots.filter { snapshot in
            guard let transfer = snapshot.transfer else {
                return linkedArchive(for: snapshot) != nil
                    && !snapshot.record.locations.contains { $0.kind == .active && $0.availability == .local }
            }
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

    // MARK: - Catalog projection (archive-only, pure)

    /// Projects archive-only generations onto the scan baseline. Pure:
    /// reads `snapshots`/`context`, never mutates observation state, never
    /// scans, never touches settings. `metadataStore` supplies persisted
    /// per-song metadata; load failures report through `onMetadataWarning`
    /// (archived-only metadata load failure warning preserved).
    func projectCatalog(
        from baselineSongs: [Song],
        showArchived: Bool,
        collaborators: [Collaborator],
        metadataStore: (any SongUserMetadataStoring)?,
        onMetadataWarning: (String) -> Void
    ) -> (scannedSongs: [Song], visibleSongs: [Song]) {
        let archivedSnapshots = archivedOnlySnapshots(from: snapshots)
        let archivedDestinationPaths = Set(archivedSnapshots.compactMap { snapshot in
            archiveDestination(for: snapshot).map(Self.vaultCanonicalPath)
        })
        let archivedSourcePaths = Set(archivedSnapshots.compactMap { snapshot in
            archiveSourcePath(for: snapshot).map { Self.vaultCanonicalPath(URL(fileURLWithPath: $0)) }
        })

        // Old cache snapshots may contain an archive projection from a previous app
        // version. Remove those paths from the scan baseline once the vault snapshot
        // is known, even when the user keeps archived projects hidden.
        let cleanScannedSongs = baselineSongs.filter { song in
            let path = Self.vaultCanonicalPath(song.folderPath)
            return !archivedDestinationPaths.contains(path) && !archivedSourcePaths.contains(path)
        }
        var archivedSongs: [Song] = []
        if showArchived, !archivedSnapshots.isEmpty {
            var metadata = Dictionary(uniqueKeysWithValues: baselineSongs.map {
                ($0.id, SongUserMetadata.from(song: $0))
            })
            do {
                metadata.merge(try metadataStore?.loadAll() ?? [:]) { _, persisted in persisted }
            } catch {
                onMetadataWarning("Archived project metadata could not be loaded: \(error.localizedDescription)")
            }
            archivedSongs = archivedSnapshots.compactMap { snapshot in
                let sourceMetadata = archiveSourcePath(for: snapshot).flatMap { metadata[$0] }
                let archiveMetadata = archiveDestination(for: snapshot).flatMap { metadata[$0.standardizedFileURL.path] }
                return makeArchivedSong(from: snapshot, metadata: sourceMetadata ?? archiveMetadata ?? metadata[snapshot.record.id.description], collaborators: collaborators)
            }
        }
        let visibleSongs = SongCatalogDeduplicator.uniqueByID(cleanScannedSongs + archivedSongs)
        return (cleanScannedSongs, visibleSongs)
    }

    private func archiveDestination(for snapshot: ProjectVaultRuntimeSnapshot) -> URL? {
        snapshot.transfer?.destinationURL ?? linkedArchive(for: snapshot)?.url
    }

    private func archiveSourcePath(for snapshot: ProjectVaultRuntimeSnapshot) -> String? {
        if let transfer = snapshot.transfer { return transfer.sourceURL.standardizedFileURL.path }
        guard let activeRoot = context?.activeRoot,
              let location = snapshot.record.locations.first(where: { $0.kind == .active && $0.rootID == activeRoot.id }) else {
            return nil
        }
        return activeRoot.fallbackURL.appendingPathComponent(location.relativePath).standardizedFileURL.path
    }

    private func makeArchivedSong(
        from snapshot: ProjectVaultRuntimeSnapshot,
        metadata: SongUserMetadata?,
        collaborators: [Collaborator]
    ) -> Song? {
        guard let archiveURL = archiveDestination(for: snapshot) else { return nil }
        let destination = archiveURL.standardizedFileURL
        let originalName = snapshot.transfer?.sourceURL.lastPathComponent ?? destination.lastPathComponent
        let detector = ProjectVersionDetector()
        let hasMaterializedDestination = FileManager.default.fileExists(atPath: destination.path)
        let versions = hasMaterializedDestination
            ? ((try? detector.detectVersions(in: destination)) ?? [])
            : []
        let title = snapshot.record.canonicalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return Song(
            folderPath: destination,
            originalFolderName: originalName,
            displayTitle: title.isEmpty ? originalName : title,
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

    // MARK: - Gating (pin OR, bound generation/restore, blocks)

    /// Settings-side Keep Local check covering every key the browser ever
    /// writes: the catalog project ID, the song ID (standardized Active path),
    /// and the transfer source path in raw, standardized, and resolved form.
    /// Always OR-ed with the runtime pin, never a replacement for it.
    static func isKeepLocalPinned(
        context: ProjectVaultPresentationContext,
        snapshot: ProjectVaultRuntimeSnapshot,
        song: Song
    ) -> Bool {
        var keys: Set<String> = [snapshot.record.id.description, song.id]
        if let sourceURL = snapshot.transfer?.sourceURL {
            keys.insert(sourceURL.path)
            keys.insert(sourceURL.standardizedFileURL.path)
            keys.insert(sourceURL.standardizedFileURL.resolvingSymlinksInPath().path)
        }
        return !context.keepLocalProjectIDs.isDisjoint(with: keys)
    }

    /// Keep Local detection for the automatic Done path, using the same
    /// identity/path keys as the snapshot and presentation logic. Every
    /// source is OR-ed; a settings-only check never clears a runtime pin.
    func isIntentionalKeepLocalSkip(for song: Song) -> Bool {
        guard let currentContext = context else { return false }
        let keepLocal = currentContext.keepLocalProjectIDs
        if keepLocal.contains(song.id) { return true }
        let songPathKeys: Set<String> = [
            song.folderPath.path,
            song.folderPath.standardizedFileURL.path,
            song.folderPath.standardizedFileURL.resolvingSymlinksInPath().path,
            Self.vaultCanonicalPath(song.folderPath),
        ]
        if !keepLocal.isDisjoint(with: songPathKeys) { return true }
        if let snapshot = snapshot(for: song) {
            if snapshot.record.pinned { return true }
            if keepLocal.contains(snapshot.record.id.description) { return true }
            if Self.isKeepLocalPinned(context: currentContext, snapshot: snapshot, song: song) { return true }
        }
        if presentation(for: song)?.isKeepLocal == true { return true }
        return snapshotsContainKeepLocalMatch(for: song, context: currentContext, keepLocal: keepLocal)
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
        for snapshot in snapshots {
            guard snapshot.record.pinned || keepLocal.contains(snapshot.record.id.description) else { continue }
            for location in snapshot.record.locations
                where location.kind == .active && location.rootID == activeRoot.id {
                let candidate = activeBase.appendingPathComponent(location.relativePath, isDirectory: true)
                if Self.vaultCanonicalPath(candidate) == songPath { return true }
            }
        }
        return false
    }

    /// Project Vault destinations are restore/review handles, never generic
    /// filesystem authority. Source-path cards also stay non-actionable while a
    /// destructive or binding review owns the project, even if the source path
    /// happens to reappear before the next catalog rebuild.
    func blocksGenericFileActions(for song: Song) -> Bool {
        guard let snapshot = snapshot(for: song) else {
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

    // MARK: - Recovery timer (dedupe, 30s backoff, busy stop, lifetime cancel)

    /// Schedules automatic recovery for `dueDate` with a 30-second local
    /// backoff over `lastRecoveryAttemptAt`. Deduplicates unchanged deadlines.
    /// Stops while busy (no new timer, existing timer kept). The timer fires
    /// `recover` then clears and fires `didRecover`; a busy check at fire
    /// time clears without recovering. All callbacks are narrow and must
    /// capture the caller weakly; this owner never retains the view model.
    func scheduleRecovery(
        isBusy: @escaping @MainActor () -> Bool,
        dueDate: Date?,
        recover: @escaping @MainActor () async -> Void,
        didRecover: @escaping @MainActor () async -> Void
    ) {
        guard !isBusy() else { return }
        guard let due = dueDate else {
            cancelRecovery()
            return
        }
        // A busy mutation lease or unavailable provider can leave the due date
        // unchanged. Back off locally instead of spinning on an overdue record.
        let deadline = max(due, lastRecoveryAttemptAt?.addingTimeInterval(30) ?? due)
        guard recoveryDeadline != deadline else { return }
        cancelRecovery()
        recoveryDeadline = deadline
        recoveryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            } catch { return }
            guard let self, !Task.isCancelled else { return }
            guard !isBusy() else {
                self.recoveryTask = nil
                self.recoveryDeadline = nil
                return
            }
            self.lastRecoveryAttemptAt = Date()
            await recover()
            guard !Task.isCancelled else { return }
            self.recoveryTask = nil
            self.recoveryDeadline = nil
            await didRecover()
        }
    }

    func cancelRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryDeadline = nil
    }

    // MARK: - Card derivation (bound generation/restore, pin OR)

    private func makePresentation(
        for song: Song,
        context: ProjectVaultPresentationContext
    ) -> ProjectVaultCardPresentation? {
        if let snapshot = snapshot(for: song) {
            let runtimePinned = snapshot.record.pinned
            var record = snapshot.record
            // Preserve pins under every identity key the runtime enforces
            // (catalog project ID, canonical/resolved source and Active paths):
            // `snapshot.record.pinned` already reflects all of them, so a
            // settings-only source-path check must never clear it.
            record.pinned = runtimePinned || Self.isKeepLocalPinned(context: context, snapshot: snapshot, song: song)
            let transferState = snapshot.transfer?.state
            let safeRestore = snapshot.restore.flatMap { restore -> VaultRestoreRecord? in
                if restore.failureReason == .archiveTransferBindingUnavailable
                    || restore.failureReason == .activeDestinationIntegrityMismatch
                    || restore.phase == .superseded
                    || restore.supersededBy != nil {
                    return restore
                }
                if let location = restore.linkedArchiveLocation,
                   restore.archiveTransferID == nil, restore.archiveTransferState == nil,
                   let root = context.archiveRoot, root.isEnabled, root.role == .archive,
                   let resolvedRoot = try? root.resolvedURL(using: FoundationSecurityScopedBookmarks()),
                   let linkedURL = ProjectArchiveLocationResolver(rootID: root.id, rootURL: resolvedRoot).resolve(location),
                   Self.vaultCanonicalPath(linkedURL) == Self.vaultCanonicalPath(restore.archiveGenerationURL),
                   restore.projectID == snapshot.record.id,
                   snapshot.record.locations.contains(where: {
                       $0.kind == .archive && $0.rootID == location.rootID && $0.relativePath == location.relativePath
                   }) {
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
                restore: safeRestore,
                linkedArchiveAvailability: linkedArchive(for: snapshot)?.location.availability,
                isReadyToFreeSpace: isReadyToFreeSpace(
                    snapshot: snapshot,
                    song: song,
                    context: context,
                    record: record,
                    runtimePinned: runtimePinned,
                    isArchiveDestinationProjection: isArchiveDestinationProjection
                ),
                isVerifiedCopy: isVerifiedCopy(
                    snapshot: snapshot,
                    context: context,
                    isArchiveDestinationProjection: isArchiveDestinationProjection
                )
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

    /// Persistent "Ready to free space" readiness, derived from persisted
    /// transfer evidence plus the retained Active location — never from
    /// ephemeral queue status. Requires a verified terminal generation bound
    /// to this project, a still-existing Active source that is not the archive
    /// projection, no Keep Local pin (runtime or settings), and live
    /// free-space settings. Readiness alone never authorizes deletion: the
    /// offered action routes through the existing bound manual archive
    /// capture for a fresh confirmation.
    private func isReadyToFreeSpace(
        snapshot: ProjectVaultRuntimeSnapshot,
        song: Song,
        context: ProjectVaultPresentationContext,
        record: ProjectRecord,
        runtimePinned: Bool,
        isArchiveDestinationProjection: Bool
    ) -> Bool {
        guard context.allowsFreeSpaceOffer,
              let transfer = snapshot.verifiedTerminalTransfer,
              context.generationReviewResolver?.resolveGeneration(
                  transfer.destinationURL,
                  projectID: transfer.projectID,
                  transferID: transfer.id
              ) != nil,
              !isArchiveDestinationProjection,
              FileManager.default.fileExists(atPath: transfer.sourceURL.path),
              snapshot.record.locations.contains(where: { $0.kind == .active })
        else {
            return false
        }
        return snapshot.isReadyToFreeSpace(
            localActiveRetained: true,
            isBoundGeneration: true,
            isKeepLocal: runtimePinned || record.pinned
        )
    }

    /// Copy-only verified generation with the Active copy retained: a valid
    /// manifest envelope (via `verifiedTerminalTransfer`) AND a generation
    /// that still exists in the configured namespace (not merely a lexical
    /// bound path), with the Active location retained. Reported separately
    /// from workflow status without hiding the project; Keep Local and the
    /// free-space offer take precedence in the presentation itself.
    private func isVerifiedCopy(
        snapshot: ProjectVaultRuntimeSnapshot,
        context: ProjectVaultPresentationContext,
        isArchiveDestinationProjection: Bool
    ) -> Bool {
        guard let transfer = snapshot.verifiedTerminalTransfer,
              context.generationReviewResolver?.resolveGeneration(
                  transfer.destinationURL,
                  projectID: transfer.projectID,
                  transferID: transfer.id
              ) != nil,
              !isArchiveDestinationProjection,
              snapshot.record.locations.contains(where: { $0.kind == .active })
        else {
            return false
        }
        return true
    }

    // MARK: - Canonical path utilities (pure)

    static func vaultCanonicalPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
        for alias in ["/private/var", "/private/tmp"] {
            if path == alias { return String(alias.dropFirst("/private".count)) }
            if path.hasPrefix(alias + "/") { return String(path.dropFirst("/private".count)) }
        }
        return path
    }

    static func vaultContains(_ root: URL, _ candidate: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count >= rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
