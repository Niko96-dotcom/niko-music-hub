import AppCore
import Combine
import Foundation
import NikoMusicCore
import ProjectVaultRuntime

/// The Archive Browser's composition for its views. Each set of state lives in
/// one owner with its rules (the "State owners" section); this type wires them,
/// holds the song catalog and its one writer, the footer and the root reset, and
/// offers the intents that cross owners (the extension files). Views observe this
/// object: every owner's publish is forwarded here at once.
@MainActor
public final class ArchiveBrowserViewModel: ObservableObject {
    /// Declared, not synthesized. The synthesized getter finds a publisher in the first
    /// `@Published` property's storage, walking the stored properties on every access;
    /// without one it returns a fresh publisher each time, so forwarding would depend on
    /// `footer` staying `@Published` here. `@Published` sends through this one.
    /// `nonisolated(unsafe)`: the protocol requirement is nonisolated and the publisher is
    /// not `Sendable`; every send happens on the main actor, and the publisher guards its
    /// own subscriber list.
    public nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()

    // MARK: - Dependencies

    let settingsStore: SettingsStore
    /// Display-only settings. Writes and Vault decisions use `library.loadSettingsForWrite()`.
    let appSettings: AppSettingsObserver
    /// Settings-pane deep links (Vault status row → Settings → Vault).
    let router: QuickAccessRouter
    let diagnostics: Diagnostics
    let fileActions: any FileActions
    let jobStatusCenter: ShellJobStatusCenter
    let collaboratorStore: (any CollaboratorStoring)?
    let archiveRootWatcher: (any ArchiveRootWatching)?
    let runtime: MusicHubRuntimeEnvironment
    let scanOverride: (([URL]) async throws -> ScanResult)?
    let incrementalRescanHold: (() async -> Void)?
    let bookmarkProvider: any SecurityScopedBookmarkProviding
    let projectVaultRuntime: (any ProjectVaultOperating)?
    let projectCatalogStore: SQLiteProjectCatalogStore?
    let identityReviewViewModel: ProjectIdentityReviewViewModel
    private let processRunner: any StreamingExternalProcessRunning
    private let opener: MusicItemOpener
    private let browseRefreshDriver: ArchiveBrowseRefreshDriver
    public var requestConverterHandoff: ((URL) -> Void)?

    // MARK: - State owners

    /// The loaded roots, their access, the first-run state and the scan state
    /// (scanning flag, scan error, diagnostics, root generation).
    private(set) lazy var library = ArchiveLibraryModel(
        settingsStore: settingsStore,
        appSettings: appSettings,
        diagnostics: diagnostics,
        runtime: runtime,
        bookmarkProvider: bookmarkProvider,
        host: ArchiveLibraryHost(
            raiseWarning: { [weak self] warning in self?.recordPersistenceWarning(warning) },
            resolveWarning: { [weak self] kind in self?.resolveFooterWarning(kind) },
            rootsDidChange: { [weak self] in self?.scanOrchestrator.invalidateForRootChange() },
            scanningDidChange: { [weak self] in self?.publishShellJobStatus() }
        )
    )
    /// Runs full and incremental scans off the main actor; this view model is its host.
    lazy var scanOrchestrator = ArchiveScanOrchestrator(host: self)
    /// Scan reconciliation with stored metadata, the index snapshot and per-song integrity.
    let catalog: ArchiveCatalogCoordinator
    /// Browse inputs (search text, shelf, collaborator, filters, sort, hidden
    /// songs), the list they produce and the reusable search index. It reads the
    /// visible catalog and the scan's skipped entries; applied results reconcile
    /// the selection.
    private(set) lazy var browse = ArchiveBrowseModel(
        refreshDriver: browseRefreshDriver,
        source: ArchiveBrowseSource(
            songs: { [weak self] in self?.songs ?? [] },
            skippedEntries: { [weak self] in self?.scanDiagnostics?.skippedEntries ?? [] },
            didApplyResults: { [weak self] in self?.reconcileSelectedSong(requireVisibleInFilteredList: true) }
        )
    )
    /// The page (board, detail, list, analytics), the selected song, the detail's
    /// disclosures and the analytics snapshot. Every write of the selection
    /// reaches `selectionDidChange(previousSongID:)`.
    private(set) lazy var page = ArchivePageModel(selectionDidChange: { [weak self] previousSongID in
        self?.selectionDidChange(previousSongID: previousSongID)
    })
    /// The archive's playback owner. Every write of the selection reaches it, and every
    /// view that shows playback gets it from here. It pauses on the context's recording signal.
    let previewSession: ArchivePreviewSession
    /// BPM/key of the main preview and the project's plug-ins, with the rules
    /// that keep those caches true to the catalog. Reads only the selection.
    private(set) lazy var songAnalysis = ArchiveSongAnalysisModel(
        plugins: ArchiveCPRPluginCoordinator(processRunner: processRunner),
        selectedSong: { [weak self] in self?.page.selectedSong }
    )
    /// Collaborator suggestions, duplicate hints, the missing-audio summary and
    /// the "until the next scan" dismissals. `refreshIntelligence()` feeds it.
    let intelligence = ArchiveIntelligenceModel()
    /// The collaborator address book and a removal waiting for confirmation.
    private(set) lazy var addressBook = ArchiveAddressBookModel(
        store: collaboratorStore,
        diagnostics: diagnostics,
        reportWarning: { [weak self] warning in self?.recordPersistenceWarning(warning) }
    )
    /// Opening a project or preview, revealing files and writing the exports,
    /// inside the archive's allowed roots and the Vault block; the nearby open
    /// error, the dry-run path and the export paths.
    private(set) lazy var fileAccess = ArchiveFileAccessModel(
        opener: opener,
        fileActions: fileActions,
        diagnostics: diagnostics,
        dryRunOpen: runtime.dryRunOpen,
        host: ArchiveFileAccessHost(
            songs: { [weak self] in self?.songs ?? [] },
            roots: { [weak self] in self?.roots ?? [] },
            outputFolder: { [weak self] in
                self?.appSettings.settings.outputFolder.url ?? AppSettings.default.outputFolder.url
            },
            writeProtectedRoots: { [weak self] in
                guard let self else { throw ArchiveWriteGuardError.settingsUnreadable }
                return try self.library.writeProtectedRoots()
            },
            isVaultBlocked: { [weak self] song in self?.blocksGenericProjectVaultFileActions(for: song) ?? true },
            vaultBlockReason: { [weak self] song in self?.projectOpenBlockReason(for: song) },
            scanDiagnostics: { [weak self] in self?.scanDiagnostics },
            exportContexts: { [weak self] in
                ArchiveDiagnosticsExportContexts(
                    search: self?.browse.searchExportContext(),
                    skippedSearch: self?.browse.skippedSearchExportContext(),
                    selectedSong: self?.page.selectedSongExportContext()
                )
            },
            reportStatus: { [weak self] message in self?.setStatusMessage(message) }
        )
    )
    /// Metadata edits: mutation, gate and persistence ordering, notes/status undo,
    /// repair IDs and delayed index persistence. The host contract is built once
    /// here with weak captures and fails closed when this view model is gone
    /// (blocked gates, nil snapshots no-op, no fake generation).
    private(set) lazy var metadataEditing: ArchiveMetadataEditingCoordinator = {
        ArchiveMetadataEditingCoordinator(
            catalog: self.catalog,
            host: ArchiveMetadataEditingHost(
                currentSongs: { [weak self] in self?.songs },
                currentScannedSongs: { [weak self] in self?.scannedSongs },
                currentCollaborators: { [weak self] in self?.collaborators },
                currentRoots: { [weak self] in self?.roots },
                currentGeneration: { [weak self] in self?.rootGeneration },
                currentScanDate: { [weak self] in
                    guard let self else { return nil }
                    return self.scanDiagnostics?.scannedAt
                },
                isVaultBlocked: { [weak self] song in
                    self?.blocksGenericProjectVaultFileActions(for: song) ?? true
                },
                canMutateStatus: { [weak self] song in
                    self?.canMutateWorkflowStatus(for: song) ?? false
                },
                canArchive: { [weak self] song in
                    self?.canArchiveInProjectVault(song) ?? false
                },
                requestDoneArchive: { [weak self] song in
                    self?.requestWorkflowDoneArchive(for: song)
                },
                revokeDoneWork: { [weak self] songID in
                    self?.revokeBoundDoneWork(for: songID)
                },
                applyReplacement: { [weak self] updated in
                    self?.applyCatalogEdit(.replace([updated]))
                },
                refreshSongDetailsWarning: { [weak self] warning in
                    self?.refreshSongDetailsWarning(warning)
                },
                reportWarning: { [weak self] warning in
                    self?.recordPersistenceWarning(warning)
                },
                reportStatus: { [weak self] message in
                    self?.setStatusMessage(message)
                },
                reportVaultStatus: { [weak self] message in
                    self?.setProjectVaultStatusMessage(message)
                }
            )
        )
    }()
    /// Vault settings context, health, snapshots and their path index, the card
    /// cache, the archived count, the "Show archived" choice and the automatic
    /// recovery timer.
    let vaultObservation = ArchiveVaultObservation()
    /// The Vault transfer queue, retries, stop and capacity accounting.
    let vaultOperations = ProjectVaultOperationCoordinator()
    /// The Vault dialogs the page presents (archive/Done confirmation, restore,
    /// identity review, stop transfer), the bound-authorization capture before the
    /// archive dialog, restore progress, and whether quit stopped the Vault.
    let vaultDialogs = ArchiveVaultDialogsModel()

    /// Each owner's publishes, forwarded to this object (`forwardChanges(of:)`).
    private var ownerChangeForwarding: [AnyCancellable] = []
    var storedSettingsCancellable: AnyCancellable?

    // MARK: - Song catalog

    /// The songs this browser holds: the scan baseline and the visible list,
    /// with an id index. `applyCatalogEdit(_:)` is its only writer: the setter
    /// is private to this file, so another writer does not compile.
    private(set) var songCatalog = SongCatalog()

    /// The visible list: the scan baseline plus archive-only Vault projections
    /// when they are shown. Views read it.
    var songs: [Song] { songCatalog.visible }

    /// Songs discovered by the configured active/scan roots. Project Vault archive
    /// generations are projected into `songs` only when the user opts into them, so
    /// toggling that view never loses the clean scan baseline.
    var scannedSongs: [Song] { songCatalog.scanned }

    func liveSong(id: String, fallback: Song) -> Song {
        songCatalog.song(id: id) ?? fallback
    }

    /// The catalog's song with this id, or nil when the catalog has none.
    func heldSong(id: String) -> Song? {
        songCatalog.song(id: id)
    }

    /// The songs of `incoming` that the catalog does not hold as they are (new or different).
    func changedSongs(in incoming: [Song]) -> [Song] {
        songCatalog.changedSongs(in: incoming)
    }

    /// The ways the catalog changes. `applyCatalogEdit(_:)` applies them.
    enum SongCatalogEdit {
        /// The cached index at launch.
        case load([Song])
        /// A scan result: unique by id and sharing the held values, then projected.
        case rescan([Song])
        /// The baseline again through the projection: Vault snapshots, "Show
        /// archived", Vault settings or roots changed.
        case reproject
        /// New Song: added to the baseline by title, then projected.
        case add(Song)
        /// Metadata edits and collaborator removal: songs replaced by id, in one
        /// batch, without a projection.
        case replace([Song])
        /// A root change: both lists empty.
        case clear
    }

    /// The catalog's writer. Projects the edit through the Vault observation,
    /// writes `songCatalog` and runs the follow-up work in one place:
    ///
    /// - a new visible list rebuilds the Vault card cache, then publishes;
    /// - any change recomputes the browse results (they reconcile the
    ///   selection), refreshes intelligence and open analytics, and lets the
    ///   song analysis follow it (`ArchiveSongAnalysisModel.follow`);
    /// - `.load`, `.rescan` and `.add` sync the repair state;
    /// - `.rescan` and `.add` persist the index (a rescan even when the songs are
    ///   equal, because the index carries the scan date), `.reproject` when the
    ///   baseline changed (the index persist writes the baseline).
    ///
    /// Returns the change, so a writer can do the work only it knows about.
    @discardableResult
    func applyCatalogEdit(_ edit: SongCatalogEdit) -> SongCatalogChange {
        var next = songCatalog
        func project(_ baseline: [Song]) -> SongCatalogChange {
            let projected = projectVaultCatalog(from: baseline)
            return next.replaceAll(scanned: projected.scannedSongs, visible: projected.visibleSongs)
        }
        let change: SongCatalogChange
        switch edit {
        case .load(let songs):
            change = project(songs)
        case .rescan(let songs):
            // Share before projecting, so the visible list shares the held values too.
            change = project(next.sharingHeldValues(songs))
        case .reproject:
            change = project(next.scanned)
        case .add(let song):
            change = project(next.scannedAdding(song))
        case .replace(let songs):
            // An archive-only projection is replaced in the visible list but never joins the baseline.
            change = next.replace(songs, isArchiveOnly: isArchivedProject)
        case .clear:
            change = next.removeAll()
        }
        if !change.isEmpty {
            if change.visibleChanged {
                // Cards ask for their Project Vault state while SwiftUI reconciles a
                // selection change: the lookup is built before the publish.
                rebuildProjectVaultPresentationCache(for: next.visible, notifyWhenChanged: false)
                objectWillChange.send()
            }
            songCatalog = next
            refreshAfterCatalogChange()
            songAnalysis.follow(
                change,
                remainingSongIDs: { Set(songs.map(\.id)) },
                pluginsSectionExpanded: page.pluginsSectionExpanded
            )
        }
        switch edit {
        case .load:
            syncMetadataRepairState()
        case .rescan, .add:
            syncMetadataRepairState()
            scheduleIndexPersist(afterNanoseconds: 0)
        case .reproject:
            if change.scannedChanged {
                scheduleIndexPersist(afterNanoseconds: 0)
            }
        case .replace:
            // `ArchiveMetadataEditingCoordinator` owns the delayed index persist of edits.
            break
        case .clear:
            // The root reset cancels pending persists and clears the repair state itself.
            break
        }
        return change
    }

    /// The browse follow-up of a catalog change (and of new scan diagnostics,
    /// whose skipped entries the browse list shows): recompute the browse results
    /// (they reconcile the selection) and refresh intelligence.
    func refreshAfterCatalogChange() {
        browse.recompute()
        refreshIntelligence()
        // Analytics stays on screen (a `switch` case, no re-appear), so a scan
        // or status edit that lands while it is open must refresh the snapshot.
        // Browse inputs (keystrokes, filters, sort) and selection go through
        // other paths and stay cheap: no history read there. Outside analytics
        // the snapshot stays lazy and is rebuilt on entry.
        if page.viewMode == .analytics {
            refreshAnalytics()
        }
    }

    // MARK: - Root reset

    /// A root change (or Clear Scan Results): every owner drops what it holds for
    /// the old roots, in this order:
    ///
    /// 1. Vault work and dialogs stop first, so nothing queued for the old roots
    ///    runs while the rest resets.
    /// 2. The owners reset their own state; the order among them does not matter.
    /// 3. `applyCatalogEdit(.clear)` comes last: its browse recompute must see the
    ///    reset browse inputs and the cleared scan diagnostics, and its per-song
    ///    step drops every BPM/key result and plug-in summary.
    /// 4. The status line, after the edit, so it is the one that shows.
    func clearRootBoundArchiveState(statusMessage nextStatusMessage: String?) {
        cancelPendingProjectVaultOperations()
        vaultOperations.clearAllOperationMessages()
        intelligence.clearForRootChange()
        metadataEditing.clearForRootChange()
        songAnalysis.clearForRootChange()
        clearFooterWarning()
        scanOrchestrator.clearPendingPaths()
        previewSession.clear()
        ArchivePreviewPlayer.clearMetadataCaches()
        browse.clearForRootChange()
        page.clearForRootChange()
        vaultObservation.clearForRootChange(notifyWhenChanged: false)
        library.clearForRootChange()
        applyCatalogEdit(.clear)
        setStatusMessage(nextStatusMessage)
    }

    // MARK: - Footer

    /// What the archive footer shows. `ArchiveFooterStatus` owns the rules; the
    /// footer methods at the end of this file are the only writers.
    @Published private(set) var footer = ArchiveFooterStatus()
    var statusMessage: String? { footer.text }
    var statusBaseMessage: String? { footer.message }
    var persistenceWarningMessage: String? { footer.warning?.text }

    // MARK: - Read-only peers of the owners
    //
    // Kept for the scan host, the edit host and the existing views and tests;
    // none stores state of its own.

    /// The address book's list: the projections, the scan and the metadata
    /// edits resolve collaborator names against it.
    var collaborators: [Collaborator] { addressBook.collaborators }
    var archivedProjectCount: Int { vaultObservation.archivedCount }
    /// Sidebar Project Vault provider status (NMH-057).
    var projectVaultHealth: ProjectVaultHealth { vaultObservation.health }
    var projectVaultPresentationContext: ProjectVaultPresentationContext? { vaultObservation.context }
    var projectVaultPresentationsBySongID: [String: ProjectVaultCardPresentation] { vaultObservation.presentationsBySongID }
    var projectVaultSnapshots: [ProjectVaultRuntimeSnapshot] { vaultObservation.snapshots }
    var projectVaultRecoveryDeadline: Date? { vaultObservation.recoveryDeadline }
    var projectVaultBusySongIDs: Set<String> { vaultOperations.busySongIDs }
    var projectVaultPendingOperations: [ProjectVaultOperationCoordinator.QueuedOperation] { vaultOperations.pendingOperations }
    var projectVaultActiveOperation: ProjectVaultOperationCoordinator.QueuedOperation? { vaultOperations.activeOperation }
    var projectVaultOperationMessages: [String: String] { vaultOperations.operationMessages }
    var projectVaultQueueFailures: [String] { vaultOperations.queueFailures }
    var projectVaultQueueBatchCount: Int { vaultOperations.queueBatchCount }
    var vaultQueueStoppedIDsForBatch: Set<String> { vaultOperations.stoppedIDsForBatch }
    var vaultQueueCanceledIDsForBatch: Set<String> { vaultOperations.canceledIDsForBatch }
    var vaultQueueStoppedRequestCountForBatch: Int { vaultOperations.stoppedRequestCountForBatch }
    var vaultQueueCanceledRequestCountForBatch: Int { vaultOperations.canceledRequestCountForBatch }
    var projectVaultRetryTasks: [String: Task<Void, Never>] { vaultOperations.retryTasks }
    var projectVaultRetryAttemptCounts: [String: Int] { vaultOperations.retryAttemptCounts }
    var projectVaultCapacityPostponedSongIDs: Set<String> { vaultOperations.capacityPostponedSongIDs }
    var projectVaultQueueTask: Task<Void, Never>? { vaultOperations.queueTask }
    /// Songs whose stored details are corrupt: edits are paused and Repair
    /// Song Details is offered.
    var metadataRepairSongIDs: Set<String> { metadataEditing.repairSongIDs }
    /// Delayed index-persist handle (tests).
    var indexPersistTask: Task<Void, Never>? { metadataEditing.indexPersistTask }
    /// Undo stack for workflow-status and metadata edits. Owned by
    /// `ArchiveMetadataEditingCoordinator` (owned/injected/weak window-bound
    /// managers plus the weak undo target). SwiftUI's main window
    /// (`AppKitWindow`) answers `undo:` itself from its own `undoManager`, so
    /// native Edit → Undo only works when registrations land on that manager.
    /// `ArchiveWorkflowUndoBridge` binds it via `bindWindowUndoManager` while
    /// this pane is the active tool; otherwise the owned stack is the
    /// fallback. Tests inject via `bindInjectedUndoManager`. Undo of Mark
    /// Done is status-only.
    var workflowUndoManager: UndoManager? { metadataEditing.effectiveUndoManager }
    var ownedWorkflowUndoManager: UndoManager { metadataEditing.ownedUndoManager }
    var injectedWorkflowUndoManager: UndoManager? { metadataEditing.injectedUndoManager }
    /// Window-owned manager captured by the bridge lifecycle. Weak: the
    /// window owns it; when the window goes away this nils and the owned
    /// stack resumes. Set/cleared only through `bindWindowUndoManager` /
    /// `unbindWindowUndoManager` by `ArchiveWorkflowUndoBridgeView`
    /// (attach/sync/detach) and only while this pane is the active tool.
    var boundWindowUndoManager: UndoManager? { metadataEditing.boundWindowUndoManager }
    var workflowUndoTarget: ArchiveWorkflowUndoTarget { metadataEditing.undoTarget }
    /// Intentional window-manager binding for the native bridge. Scrubbing
    /// removes only this owner's actions, preserving unrelated window actions.
    func bindWindowUndoManager(_ manager: UndoManager?) {
        metadataEditing.bindWindowUndoManager(manager)
    }
    func unbindWindowUndoManager() {
        metadataEditing.unbindWindowUndoManager()
    }
    /// Intentional test injection. Replaces the former writable
    /// `workflowUndoManager` alias.
    func bindInjectedUndoManager(_ manager: UndoManager?) {
        metadataEditing.bindInjectedUndoManager(manager)
    }

    var showsSidebarMorePanel: Bool {
        !roots.isEmpty
    }

    // MARK: - Init

    public convenience init(
        context: ToolContext,
        archiveIndexStore: (any ArchiveIndexStoring)? = nil,
        songMetadataStore: (any SongUserMetadataStoring)? = nil,
        songMetadataStorageUnavailable: Bool = false,
        archiveRootWatcher: (any ArchiveRootWatching)? = nil,
        collaboratorStore: (any CollaboratorStoring)? = nil,
        browseSearchDebounceNanoseconds: UInt64 = 200_000_000,
        runtime: MusicHubRuntimeEnvironment = .current
    ) {
        self.init(
            context: context,
            archiveIndexStore: archiveIndexStore,
            songMetadataStore: songMetadataStore,
            songMetadataStorageUnavailable: songMetadataStorageUnavailable,
            archiveRootWatcher: archiveRootWatcher,
            collaboratorStore: collaboratorStore,
            projectVaultRuntime: nil,
            browseSearchDebounceNanoseconds: browseSearchDebounceNanoseconds,
            runtime: runtime,
            scanOverride: nil
        )
    }

    public convenience init(
        context: ToolContext,
        archiveIndexStore: (any ArchiveIndexStoring)? = nil,
        songMetadataStore: (any SongUserMetadataStoring)? = nil,
        songMetadataStorageUnavailable: Bool = false,
        archiveRootWatcher: (any ArchiveRootWatching)? = nil,
        collaboratorStore: (any CollaboratorStoring)? = nil,
        projectVaultRuntime: (any ProjectVaultOperating)?,
        projectCatalogStore: SQLiteProjectCatalogStore? = nil,
        browseSearchDebounceNanoseconds: UInt64 = 200_000_000,
        runtime: MusicHubRuntimeEnvironment = .current
    ) {
        self.init(
            context: context,
            archiveIndexStore: archiveIndexStore,
            songMetadataStore: songMetadataStore,
            songMetadataStorageUnavailable: songMetadataStorageUnavailable,
            archiveRootWatcher: archiveRootWatcher,
            collaboratorStore: collaboratorStore,
            projectVaultRuntime: projectVaultRuntime,
            projectCatalogStore: projectCatalogStore,
            browseSearchDebounceNanoseconds: browseSearchDebounceNanoseconds,
            runtime: runtime,
            scanOverride: nil
        )
    }

    init(
        context: ToolContext,
        archiveIndexStore: (any ArchiveIndexStoring)? = nil,
        songMetadataStore: (any SongUserMetadataStoring)? = nil,
        songMetadataStorageUnavailable: Bool = false,
        archiveRootWatcher: (any ArchiveRootWatching)? = nil,
        collaboratorStore: (any CollaboratorStoring)? = nil,
        projectVaultRuntime: (any ProjectVaultOperating)? = nil,
        projectCatalogStore: SQLiteProjectCatalogStore? = nil,
        browseSearchDebounceNanoseconds: UInt64 = 200_000_000,
        runtime: MusicHubRuntimeEnvironment = .current,
        bookmarkProvider: any SecurityScopedBookmarkProviding = FoundationSecurityScopedBookmarks(),
        scanOverride: (([URL]) async throws -> ScanResult)?,
        incrementalRescanHold: (() async -> Void)? = nil,
        workspaceOpener: (any WorkspaceOpening)? = nil
    ) {
        self.settingsStore = context.settingsStore
        self.appSettings = context.appSettings
        self.router = context.router
        self.diagnostics = context.diagnostics
        self.fileActions = context.fileActions
        self.jobStatusCenter = context.jobStatusCenter
        self.previewSession = ArchivePreviewSession(capture: context.audioCaptureActivity)
        self.processRunner = context.processRunner
        self.collaboratorStore = collaboratorStore
        self.archiveRootWatcher = archiveRootWatcher
        self.runtime = runtime
        self.projectVaultRuntime = projectVaultRuntime
        self.projectCatalogStore = projectCatalogStore
        self.identityReviewViewModel = ProjectIdentityReviewViewModel(catalogStore: projectCatalogStore)
        self.scanOverride = scanOverride
        self.incrementalRescanHold = incrementalRescanHold
        self.bookmarkProvider = bookmarkProvider
        self.catalog = ArchiveCatalogCoordinator(
            archiveIndexStore: archiveIndexStore,
            songMetadataStore: songMetadataStore,
            songMetadataStorageUnavailable: songMetadataStorageUnavailable,
            collaboratorStore: collaboratorStore,
            diagnostics: context.diagnostics,
            settingsStore: context.settingsStore
        )
        self.browseRefreshDriver = ArchiveBrowseRefreshDriver(debounceNanoseconds: browseSearchDebounceNanoseconds)
        let dryRunOnly = runtime.dryRunOpen
        self.opener = MusicItemOpener(
            workspace: dryRunOnly ? nil : (workspaceOpener ?? AppKitWorkspaceOpener()),
            log: { [diagnostics] message in
                diagnostics.log(.info, message)
            }
        )
        wireVaultOperationCoordinator()
        forwardChanges(of: vaultOperations)
        forwardChanges(of: vaultObservation)
        forwardChanges(of: metadataEditing)
        forwardChanges(of: library)
        forwardChanges(of: browse)
        forwardChanges(of: page)
        forwardChanges(of: intelligence)
        forwardChanges(of: songAnalysis)
        forwardChanges(of: addressBook)
        forwardChanges(of: fileAccess)
        forwardChanges(of: vaultDialogs)
        library.loadRootsFromSettings()
        followStoredSettingsChanges()
        page.attach(context.navigationHistory) { [weak self] route in
            self?.restoreNavigationRoute(route)
        }
        refreshProjectVaultPresentationContext(notifyWhenChanged: false)
        addressBook.load()
        library.refreshFirstRunState()
        restartArchiveRootWatching()
        loadCachedIndexIfAvailable()
        Task {
            await recoverProjectVaultAndRefresh()
        }
        if archiveRootWatcher != nil, !roots.isEmpty, !runtime.usesFixtureRoot {
            setStatusMessage("Scanning archive...")
            Task { await scanInBackground() }
        }
    }

    /// Every settings save publishes through `appSettings` on the main queue,
    /// after the store holds it; the archive follows each one, whoever wrote it.
    /// `@Published` emits before the observer stores the value, so the reaction
    /// waits one main-queue turn: by then `appSettings.settings` is current too.
    private func followStoredSettingsChanges() {
        storedSettingsCancellable = appSettings.$settings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.followStoredSettings() }
            }
    }

    /// Views observe this object, so each owner's publish is sent here at once, at the
    /// same moment as the owner's own (willSet). The sink holds the declared publisher,
    /// not this view model, and the subscriptions end with it.
    private func forwardChanges<Owner: ObservableObject>(of owner: Owner)
        where Owner.ObjectWillChangePublisher == ObservableObjectPublisher {
        let publisher = objectWillChange
        ownerChangeForwarding.append(owner.objectWillChange.sink { _ in publisher.send() })
    }

    /// Injects the operation owner's narrow callbacks. All captures are weak;
    /// the coordinator never retains this view model.
    private func wireVaultOperationCoordinator() {
        vaultOperations.onStatus = { [weak self] message in
            self?.setProjectVaultStatusMessage(message)
        }
        vaultOperations.currentStatusBase = { [weak self] in
            self?.statusBaseMessage
        }
        vaultOperations.currentRootIDs = { [weak self] in
            self?.vaultQueueRootIDs ?? []
        }
        vaultOperations.refreshPresentationForDispatch = { [weak self] in
            self?.refreshProjectVaultPresentationContext()
        }
        vaultOperations.onActiveChanged = { [weak self] in
            self?.publishShellJobStatus()
        }
        vaultOperations.onLogStart = { [weak self] label in
            self?.diagnostics.scoped(to: .vault).log(.info, "Vault operation started (label=\(label))")
        }
        vaultOperations.onLogFinish = { [weak self] label, succeeded, stopped in
            self?.diagnostics.scoped(to: .vault).log(
                succeeded && !stopped ? .info : .error,
                "Vault operation finished (label=\(label), succeeded=\(succeeded), stopped=\(stopped))"
            )
        }
        vaultOperations.onQueueDrained = { [weak self] in
            await self?.scheduleProjectVaultRecovery()
        }
    }

    deinit {
        // Each owner cancels its own work when it is released with this view
        // model: the Vault queue and retries (`ProjectVaultOperationCoordinator`),
        // the recovery timer (`ArchiveVaultObservation`), the delayed index
        // persist (`ArchiveMetadataEditingCoordinator`), the authorization capture
        // (`ArchiveVaultDialogsModel`) and the intelligence refresh.
    }

    // MARK: - Intents across owners

    /// The By Collaborator shelf starts on the address book's first collaborator.
    func selectShelf(_ shelf: ArchiveSmartShelf) {
        browse.selectShelf(shelf, defaultCollaboratorID: collaborators.first?.id)
    }

    /// Mirrors scan and Vault-transfer activity into the shell job status center;
    /// driven by the library's `isScanning` observer and the operation owner's
    /// `onActiveChanged` hook (same timing as the former active-operation didSet).
    func publishShellJobStatus() {
        if library.isScanning {
            jobStatusCenter.setExtraJob(
                sourceID: ShellJobExtraSourceID.archiveScan,
                status: ShellJobStatusCopy.archiveScanStatus,
                cancel: { [weak self] in
                    Task { @MainActor in
                        self?.cancelScan()
                    }
                }
            )
        } else {
            jobStatusCenter.setExtraJob(sourceID: ShellJobExtraSourceID.archiveScan, status: nil)
        }

        if let operation = projectVaultActiveOperation {
            jobStatusCenter.setExtraJob(
                sourceID: ShellJobExtraSourceID.vaultTransfer,
                status: ShellJobStatusCopy.vaultTransferStatus(songName: operation.songName, progress: nil),
                cancel: { [weak self] in
                    Task { @MainActor in
                        self?.requestStopActiveProjectVaultTransfer()
                    }
                },
                quitCancel: { [weak self] in
                    Task { @MainActor in
                        self?.stopProjectVaultWorkForQuit()
                    }
                }
            )
        } else {
            jobStatusCenter.setExtraJob(sourceID: ShellJobExtraSourceID.vaultTransfer, status: nil)
        }
    }

    /// Recomputes the intelligence hints from the catalog and the address book,
    /// after the debounce. `refreshIntelligenceNow()` skips it.
    func refreshIntelligence() {
        intelligence.refresh(songs: songs, collaborators: collaborators, immediate: false)
    }

    func refreshIntelligenceNow() {
        intelligence.refresh(songs: songs, collaborators: collaborators, immediate: true)
    }

    var sidebarHealthContext: ArchiveSidebarHealthContext {
        ArchiveSidebarHealthContext.make(
            report: healthReport(),
            skippedEntryCount: scanDiagnostics?.skippedEntries.count ?? 0
        )
    }

    func healthReport() -> ArchiveHealthReport {
        ArchiveHealthReport(songs: songs, includeHidden: browse.showHiddenSongs)
    }

    func convertMainPreview(for song: Song) {
        guard let id = song.mainPreviewCandidateID,
              let url = song.previewCandidates.first(where: { $0.id == id })?.filePath else {
            return
        }
        requestConverterHandoff?(url)
    }

    func chooseTemplateFolder() -> URL? {
        fileActions.chooseDirectory(prompt: "Choose Template Folder")
    }
}

// MARK: - Footer status

/// The only writers of `footer`. Each publishes only when the footer changes,
/// so a background message that a Project Vault hold ignores costs no render.
extension ArchiveBrowserViewModel {
    func setStatusMessage(_ message: String?) {
        updateFooter { $0.show(message, from: .action) }
    }

    func setProjectVaultStatusMessage(_ message: String?) {
        updateFooter { $0.show(message, from: .projectVault) }
    }

    func setBackgroundStatusMessage(_ message: String?) {
        updateFooter { $0.show(message, from: .background) }
    }

    func recordPersistenceWarning(_ warning: String) {
        recordPersistenceWarning(ArchiveFooterStatus.Warning(warning))
    }

    func recordPersistenceWarning(_ warning: ArchiveFooterStatus.Warning) {
        updateFooter { $0.raise(warning) }
    }

    func resolveFooterWarning(_ kind: ArchiveFooterStatus.Warning.Kind) {
        updateFooter { $0.resolve(kind) }
    }

    /// Root change: no warning about the previous roots stays.
    func clearFooterWarning() {
        updateFooter { $0.clearWarning() }
    }

    /// After a song-details repair: only a song-details warning is replaced,
    /// by the catalog's current one, or cleared when the catalog has none.
    func refreshSongDetailsWarning(_ warning: String?) {
        guard footer.warning?.kind == .songDetails else { return }
        if let warning {
            recordPersistenceWarning(warning)
        } else {
            resolveFooterWarning(.songDetails)
        }
    }

    /// Clears a Project Vault message once its condition is over, only while
    /// the footer still shows it.
    func withdrawFooterMessage(_ message: String) {
        updateFooter { $0.withdraw(message) }
    }

    private func updateFooter(_ change: (inout ArchiveFooterStatus) -> Void) {
        var next = footer
        change(&next)
        guard next != footer else { return }
        footer = next
    }
}
