import AppCore
import Combine
import Foundation
import NikoMusicCore
import ProjectVaultRuntime

/// Archive shell composition and browse/selection state. Metadata editing,
/// Vault observation and operations, scanning, and audio/project analysis
/// delegate to their owners; extensions integrate their results with the UI.
@MainActor
public final class ArchiveBrowserViewModel: ObservableObject {
    // MARK: - Dependencies

    let identityReviewViewModel: ProjectIdentityReviewViewModel
    let catalog: ArchiveCatalogCoordinator
    private let browseRefreshDriver: ArchiveBrowseRefreshDriver
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
    private let processRunner: any StreamingExternalProcessRunning
    let opener: MusicItemOpener
    let pathSafety = PathSafety()
    let fileActions: any FileActions
    let settingsStore: SettingsStore
    /// Display-only settings. Writes and Vault decisions use `loadSettingsForWrite()`.
    let appSettings: AppSettingsObserver
    /// Settings-pane deep links (Vault status row → Settings → Vault).
    let router: QuickAccessRouter
    let diagnostics: Diagnostics
    let jobStatusCenter: ShellJobStatusCenter
    let collaboratorStore: (any CollaboratorStoring)?
    let archiveRootWatcher: (any ArchiveRootWatching)?
    let runtime: MusicHubRuntimeEnvironment
    let scanOverride: (([URL]) async throws -> ScanResult)?
    let incrementalRescanHold: (() async -> Void)?
    let bookmarkProvider: any SecurityScopedBookmarkProviding
    let projectVaultRuntime: (any ProjectVaultOperating)?
    let projectCatalogStore: SQLiteProjectCatalogStore?

    // MARK: - Published state

    @Published var roots: [URL] = [] {
        didSet {
            guard oldValue.standardizedArchivePaths != roots.standardizedArchivePaths else { return }
            invalidateActiveScanForRootChange()
        }
    }
    /// The songs this browser holds: the scan baseline and the visible list,
    /// with an id index. `applyCatalogEdit(_:)` is its only writer: the setter
    /// is private to this file, so another writer does not compile.
    private(set) var songCatalog = SongCatalog()

    /// The visible list: the scan baseline plus archive-only Vault projections
    /// when they are shown. Views read it.
    var songs: [Song] { songCatalog.visible }

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

    /// The By Collaborator shelf starts on the address book's first collaborator.
    func selectShelf(_ shelf: ArchiveSmartShelf) {
        browse.selectShelf(shelf, defaultCollaboratorID: collaborators.first?.id)
    }
    @Published var isScanning = false {
        didSet {
            // NMH-049: a new scan dismisses the nearby scan error.
            // Guarded so an already-clear error adds no extra publish.
            if isScanning, scanError != nil {
                scanError = nil
            }
            publishShellJobStatus()
        }
    }
    /// What the archive footer shows. `ArchiveFooterStatus` owns the rules; the
    /// footer methods at the end of this file are the only writers.
    @Published private(set) var footer = ArchiveFooterStatus()
    var statusMessage: String? { footer.text }
    var statusBaseMessage: String? { footer.message }
    var persistenceWarningMessage: String? { footer.warning?.text }
    /// NMH-049: nearby open failure recovery (footer `statusMessage` stays the log).
    @Published var openError: String?
    /// NMH-049: nearby scan failure body (footer keeps `Scan failed: …`).
    @Published var scanError: String?
    @Published var scanDiagnostics: ArchiveScanDiagnostics?
    @Published var lastDryRunLog: String?
    @Published var lastDiagnosticsExportPath: String?
    @Published var lastIndexExportPath: String?
    @Published var needsFirstRunOnboarding = false {
        didSet {
            // NMH-042: first-run overlay appear/dismiss changes layout.
            if oldValue != needsFirstRunOnboarding {
                HubAccessibilityAnnouncer.layoutChanged()
            }
        }
    }
    @Published var archiveAccessFailure: ArchiveAccessFailure?
    /// The collaborator address book and a removal waiting for confirmation.
    private(set) lazy var addressBook = ArchiveAddressBookModel(
        store: collaboratorStore,
        diagnostics: diagnostics,
        reportWarning: { [weak self] warning in self?.recordPersistenceWarning(warning) }
    )
    /// The address book's list: the projections, the scan and the metadata
    /// edits resolve collaborator names against it.
    var collaborators: [Collaborator] { addressBook.collaborators }
    /// Collaborator suggestions, duplicate hints, the missing-audio summary and
    /// the "until the next scan" dismissals. `refreshIntelligence()` feeds it.
    let intelligence = ArchiveIntelligenceModel()
    /// Archived Project Vault generations are opt-in in the browse projection so the
    /// active workspace stays calm. Turning this on exposes verified archive-only
    /// projects in their persisted workflow stage.
    @Published var showArchivedProjects = false
    /// Archived count is owned by `ArchiveVaultObservation`; this read-only
    /// peer preserves the existing view/test API with no duplicate storage.
    /// SwiftUI updates flow through the observation bridge in
    /// `wireVaultObservation()`.
    var archivedProjectCount: Int { vaultObservation.archivedCount }
    /// Single metadata-editing owner for mutation/gate/persistence ordering,
    /// notes/status undo, repair IDs, and delayed index persistence. All
    /// mutations go through the coordinator's intentional methods; these
    /// computed peers preserve read access for existing views/tests with no
    /// duplicate stored state. The view model re-emits the coordinator's
    /// publishes for SwiftUI via `wireMetadataEditing()` with a weak capture;
    /// the coordinator never retains this view model. The host contract is
    /// required and immutable: built once here with weak captures, fail-closed
    /// when the host is gone (blocked gates, nil snapshots no-op, no fake
    /// generation).
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
    /// Songs whose stored details are corrupt: edits are paused and Repair
    /// Song Details is offered. Owned by `ArchiveMetadataEditingCoordinator`;
    /// this read-only peer preserves the existing view/test API with no
    /// duplicate storage.
    var metadataRepairSongIDs: Set<String> { metadataEditing.repairSongIDs }
    /// Delayed index-persist handle. Owned by the metadata coordinator;
    /// read-only peer for existing tests.
    var indexPersistTask: Task<Void, Never>? { metadataEditing.indexPersistTask }
    /// Single observation owner for Vault settings context, health, snapshots,
    /// path index, card cache, archived count, catalog projection inputs, and
    /// recovery timer lifecycle. All mutations go through the observation's
    /// intentional methods; these computed peers preserve read access for
    /// existing views/tests with no duplicate stored state. The view model
    /// re-emits the observation's publishes for SwiftUI via
    /// `wireVaultObservation()` with weak captures; the observation never
    /// retains this view model.
    let vaultObservation = ArchiveVaultObservation()
    /// Read-only peers for the observation owner. All Vault observation writes
    /// go through `ArchiveVaultObservation` intentional operations.
    var projectVaultPresentationContext: ProjectVaultPresentationContext? { vaultObservation.context }
    var projectVaultPresentationsBySongID: [String: ProjectVaultCardPresentation] { vaultObservation.presentationsBySongID }
    var projectVaultSnapshots: [ProjectVaultRuntimeSnapshot] { vaultObservation.snapshots }
    var projectVaultRecoveryDeadline: Date? { vaultObservation.recoveryDeadline }
    /// Single owner for Vault transfer queue/retry accounting. All mutations
    /// go through `vaultOperations`; these computed peers preserve read access
    /// for existing views/tests with no duplicate stored state. The view model
    /// re-emits `objectWillChange` when the coordinator publishes so SwiftUI
    /// updates with no UI edits.
    let vaultOperations = ProjectVaultOperationCoordinator()
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
    @Published var projectVaultRestoreRequest: ProjectVaultRestoreRequest?
    @Published var projectVaultRestoreProgress: ProjectVaultRestoreProgress?
    var boundArchiveCaptureSongID: String?
    @Published var pendingArchiveConfirmation: ProjectVaultArchiveConfirmation?
    @Published var pendingStopTransferConfirmation = false
    /// Set once quit has stopped the Vault queue (ADR-019): no new operation is
    /// queued and no recovery is scheduled for the exiting app to cut off.
    var projectVaultStoppedForQuit = false
    @Published var identityReviewPresentation: ProjectIdentityReviewPresentation?
    /// A Vault dialog that `ArchiveBrowserView` presents is waiting. SwiftUI
    /// shows it only once no other sheet is open, so the song detail closes
    /// "Manage storage" for it instead of hiding it until the user does.
    var hasPendingProjectVaultDialog: Bool {
        pendingArchiveConfirmation != nil
            || projectVaultRestoreRequest != nil
            || identityReviewPresentation != nil
            || pendingStopTransferConfirmation
    }
    /// Sidebar Project Vault provider status (NMH-057). Owned by
    /// `ArchiveVaultObservation`; this read-only peer preserves the existing
    /// view API with no duplicate storage.
    var projectVaultHealth: ProjectVaultHealth { vaultObservation.health }

    // MARK: - Stored state

    var rootGeneration: UInt64 = 0
    lazy var scanOrchestrator = ArchiveScanOrchestrator(host: self)
    /// Songs discovered by the configured active/scan roots. Project Vault archive
    /// generations are projected into `songs` only when the user opts into them, so
    /// toggling that view never loses the clean scan baseline.
    var scannedSongs: [Song] { songCatalog.scanned }
    var projectVaultRestoreOptionsLoading = false
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
    var vaultOperationsCancellable: AnyCancellable?
    var vaultObservationCancellable: AnyCancellable?
    var metadataEditingCancellable: AnyCancellable?
    var songAnalysisCancellable: AnyCancellable?
    var intelligenceCancellable: AnyCancellable?
    var browseCancellable: AnyCancellable?
    var pageCancellable: AnyCancellable?
    var addressBookCancellable: AnyCancellable?
    /// V3 bound-authorization capture state. Every confirmation request bumps
    /// `projectVaultAuthCaptureGeneration` and replaces
    /// `projectVaultAuthCaptureTask`; a capture only presents its dialog when
    /// its generation is still current and the task was not cancelled, so a
    /// stale or superseded capture can never produce a surprise late modal.
    var projectVaultAuthCaptureGeneration: UInt64 = 0
    var projectVaultAuthCaptureTask: Task<Void, Never>?
    /// Deterministic seam for behavioral tests: awaited at the start of every
    /// bound-authorization capture so settings/roots/source changes can be
    /// applied while a confirmation is still in flight.
    var projectVaultAuthCaptureProbe: (@Sendable () async -> Void)?
    // Vault observation storage moved to `ArchiveVaultObservation`
    // (context, health, snapshots, path index, card cache, archived count,
    // recovery timer). Read-only peers above preserve the view API; writes
    // go through the observation's intentional methods.
    /// Keeps security-scoped access alive for bookmarked roots while the model lives.
    var securityScopedRootAccesses: [SecurityScopedRootAccess] = []
    /// The stored roots and Vault settings the archive last loaded; nil while
    /// settings are unreadable. `followStoredSettings()` compares against it.
    var followedSettings: ArchiveFollowedSettings?
    var storedSettingsCancellable: AnyCancellable?
    public var requestConverterHandoff: ((URL) -> Void)?

    // MARK: - Computed

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
        wireVaultObservation()
        wireMetadataEditing()
        songAnalysisCancellable = songAnalysis.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        intelligenceCancellable = intelligence.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        browseCancellable = browse.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        pageCancellable = page.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        addressBookCancellable = addressBook.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        loadRootsFromSettings()
        followStoredSettingsChanges()
        page.attach(context.navigationHistory) { [weak self] route in
            self?.restoreNavigationRoute(route)
        }
        refreshProjectVaultPresentationContext(notifyWhenChanged: false)
        addressBook.load()
        refreshFirstRunState()
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

    /// Wire the single observation owner: forward its publishes into this
    /// observable object (views keep reading the view-model peers with no UI
    /// edits). The capture is weak; the observation never retains this view
    /// model. Recovery timer lifetime is owned by the observation's `deinit`.
    private func wireVaultObservation() {
        vaultObservationCancellable = vaultObservation.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// Wire the single operation owner: forward its publishes into this
    /// observable object (views keep reading the view-model peers with no UI
    /// edits) and inject the narrow vault callbacks. All captures are weak;
    /// the coordinator never retains this view model.
    private func wireVaultOperationCoordinator() {
        vaultOperationsCancellable = vaultOperations.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
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

    /// Wire the single metadata-editing owner: forward its publishes into this
    /// observable object (views keep reading the view-model peers with no UI
    /// edits). The host contract is built once in the lazy owner factory above;
    /// this only subscribes. The capture is weak; the coordinator never retains
    /// this view model.
    private func wireMetadataEditing() {
        metadataEditingCancellable = metadataEditing.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    deinit {
        // Lifetime retry/queue cancellation is owned by
        // `ProjectVaultOperationCoordinator.deinit`, which cancels its own
        // Sendable task handles directly (`Task.cancel()` is thread-safe, so
        // no actor-isolated call is needed here). Releasing this view model
        // releases the coordinator, which cancels any sleeping retry and the
        // running queue task so no callback fires after the owner is gone.
        // Recovery timer lifetime is owned by `ArchiveVaultObservation.deinit`.
        // Delayed index persistence is owned by
        // `ArchiveMetadataEditingCoordinator.deinit`.
        projectVaultAuthCaptureTask?.cancel()
    }

    // MARK: - Helpers

    /// Mirrors scan and Vault-transfer activity into the shell job status center;
    /// driven by the `isScanning` observer and the operation owner's
    /// `onActiveChanged` hook (same timing as the former active-operation didSet).
    func publishShellJobStatus() {
        if isScanning {
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
