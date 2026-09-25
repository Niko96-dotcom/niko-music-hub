import AppCore
import Combine
import Foundation
import NikoMusicCore

/// Archive shell view model. Roots, browse, selection, scan, metadata, exports,
/// collaborators, intelligence, and status live in `ArchiveBrowserViewModel+*.swift`
/// extensions; mixdown/CPR analysis is delegated to dedicated coordinators.
@MainActor
public final class ArchiveBrowserViewModel: ObservableObject {
    // MARK: - Types

    /// Archive page layout: the board is home, opening a card goes to
    /// fullscreen detail, and the classic sidebar+detail list stays reachable.
    enum ArchiveViewMode {
        case board
        case boardDetail
        case list
        case analytics
    }

    // MARK: - Dependencies

    let searchInput = ArchiveSearchInput()
    let identityReviewViewModel: ProjectIdentityReviewViewModel
    let catalog: ArchiveCatalogCoordinator
    let browseRefreshDriver: ArchiveBrowseRefreshDriver
    let mixdownAnalysis = ArchiveMixdownAnalysisCoordinator()
    let cprPlugins = ArchiveCPRPluginCoordinator()
    let opener: MusicItemOpener
    let pathSafety = PathSafety()
    let fileActions: any FileActions
    let settingsStore: SettingsStore
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

    @Published public var roots: [URL] = [] {
        didSet {
            guard oldValue.standardizedArchivePaths != roots.standardizedArchivePaths else { return }
            invalidateActiveScanForRootChange()
        }
    }
    @Published var songs: [Song] = [] {
        willSet {
            // Cards ask for their Project Vault state while SwiftUI reconciles a
            // selection change. Build that immutable lookup before publishing a
            // new catalog so card rendering never needs to decode settings or
            // canonicalize filesystem paths.
            guard newValue != songs else { return }
            songsByID = Dictionary(
                newValue.map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            rebuildProjectVaultPresentationCache(for: newValue, notifyWhenChanged: false)
        }
    }
    /// O(1) live catalog lookup for detail views. Rebuilt before `songs`
    /// publishes so every body pass sees a cache matching the new snapshot.
    private var songsByID: [String: Song] = [:]

    func liveSong(id: String, fallback: Song) -> Song {
        songsByID[id] ?? fallback
    }
    @Published var filteredSongs: [Song] = []
    @Published var searchMatchSummaries: [String: String] = [:]
    @Published var skippedSearchMatches: [SkippedEntrySearchResult] = []
    @Published var selectedShelf: ArchiveSmartShelf = .allSongs
    @Published var selectedCollaboratorID: String?
    @Published var selectedSong: Song? {
        didSet {
            // NMH-049: a song change dismisses the nearby open error.
            // Guarded so an already-clear error adds no extra publish.
            if oldValue?.id != selectedSong?.id, openError != nil {
                openError = nil
            }
        }
    }
    /// Song-detail "Details" disclosure state — hoisted so the browser-level "d"
    /// keyboard shortcut can toggle it.
    @Published var songDetailsExpanded = false
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
    @Published var statusMessage: String?
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
    @Published var collaborators: [Collaborator] = []
    @Published var showHiddenSongs = false
    @Published var sortMode: ArchiveBrowseSortMode = .recentCPR
    @Published var browseFilter: ArchiveBrowseFilter = []
    @Published var pendingCollaboratorSuggestions: [CollaboratorSuggestion] = []
    /// Dismissed suggestion identities (`CollaboratorSuggestion.id` =
    /// songID + collaboratorID) for the current scan. Dismissal hides a row
    /// "until the next scan": immediate and debounced/async intelligence
    /// refreshes filter these out at apply time, so a held older refresh can
    /// never reinsert one. Cleared when a fresh scan starts or scan results
    /// are cleared. Never persisted; per-instance only.
    var dismissedCollaboratorSuggestionIDs: Set<String> = []
    @Published var pendingCollaboratorRemoval: Collaborator?
    @Published var duplicateSongHints: [DuplicateSongHint] = []
    @Published var missingAudioReport: MissingAudioReport?
    /// Archived Project Vault generations are opt-in in the browse projection so the
    /// active workspace stays calm. Turning this on exposes verified archive-only
    /// projects in their persisted workflow stage.
    @Published var showArchivedProjects = false
    @Published var archivedProjectCount = 0
    @Published var mixdownBPMBySongID: [String: MixdownBPMEstimate] = [:]
    @Published var mixdownKeyBySongID: [String: MixdownKeyEstimate] = [:]
    @Published var cprPluginSummaryByCPRPath: [String: CPRPluginSummary] = [:]
    @Published var pluginsSectionExpanded = false
    /// Songs whose stored details are corrupt: edits are paused and Repair
    /// Song Details is offered (mirrors the catalog's per-song gate).
    @Published var metadataRepairSongIDs: Set<String> = []
    @Published var projectVaultBusySongIDs: Set<String> = []
    @Published var projectVaultPendingOperations: [ProjectVaultQueuedOperation] = []
    @Published var projectVaultActiveOperation: ProjectVaultQueuedOperation? {
        didSet { publishShellJobStatus() }
    }
    @Published var projectVaultOperationMessages: [String: String] = [:]
    @Published var projectVaultRestoreRequest: ProjectVaultRestoreRequest?
    @Published var projectVaultRestoreProgress: ProjectVaultRestoreProgress?
    var boundArchiveCaptureSongID: String?
    @Published var pendingArchiveConfirmation: ProjectVaultArchiveConfirmation?
    @Published var pendingStopTransferConfirmation = false
    @Published var identityReviewPresentation: ProjectIdentityReviewPresentation?
    /// Sidebar Project Vault provider status (NMH-057). Refreshed with the
    /// card context so the render path never touches `SettingsStore`.
    @Published var projectVaultHealth = ProjectVaultHealth(
        providerStatus: .notConfigured,
        lastSuccessfulVerificationAt: nil,
        hasIndependentBackup: false
    )
    @Published var viewMode: ArchiveViewMode = .board {
        didSet {
            // NMH-042: board ↔ list ↔ boardDetail ↔ analytics changes layout.
            if oldValue != viewMode {
                HubAccessibilityAnnouncer.layoutChanged()
            }
        }
    }
    /// Compact list shows the detail page only after an explicit open (double-click / Return).
    @Published var listShowsDetail = false
    @Published var analyticsSnapshot: ArchiveAnalyticsSnapshot?

    // MARK: - Stored state

    var rootGeneration: UInt64 = 0
    lazy var scanOrchestrator = ArchiveScanOrchestrator(host: self)
    /// Songs discovered by the configured active/scan roots. Project Vault archive
    /// generations are projected into `songs` only when the user opts into them, so
    /// toggling that view never loses the clean scan baseline.
    var scannedSongs: [Song] = []
    // Updated before filteredSongs publishes, so Board uses the applied query mode.
    var isSearching = false
    var projectVaultRestoreOptionsLoading = false
    /// Undo stack for workflow-status and metadata edits.
    ///
    /// SwiftUI's main window (`AppKitWindow`) answers `undo:` itself from its
    /// own `undoManager`, so native Edit → Undo only works when registrations
    /// land on that manager. `ArchiveWorkflowUndoBridge` binds it here as
    /// `boundWindowUndoManager` while this pane is the active tool; otherwise
    /// the owned stack is the fallback. Tests may inject a manager by assigning
    /// `workflowUndoManager`. Registrations target `workflowUndoTarget` (weak
    /// back-reference) so the undo stack cannot keep the view model alive.
    /// Undo of Mark Done is status-only.
    let ownedWorkflowUndoManager = UndoManager()
    let workflowUndoTarget = ArchiveWorkflowUndoTarget()
    var injectedWorkflowUndoManager: UndoManager?
    /// Window-owned manager captured by the bridge lifecycle. Weak: the
    /// window owns it; when the window goes away this nils and the owned
    /// stack resumes. Set/cleared only by `ArchiveWorkflowUndoBridgeView`
    /// (attach/sync/detach) and only while this pane is the active tool.
    weak var boundWindowUndoManager: UndoManager?
    var workflowUndoManager: UndoManager? {
        get { injectedWorkflowUndoManager ?? boundWindowUndoManager ?? ownedWorkflowUndoManager }
        set { injectedWorkflowUndoManager = newValue }
    }
    var projectVaultQueueTask: Task<Void, Never>?
    var projectVaultStopRequested = false
    var projectVaultQueueFailures: [String] = []
    var projectVaultQueueBatchCount = 0
    /// P2 batch-stop truth: per-batch set of songIDs whose operation was
    /// interrupted via Stop Transfer / task cancellation. Per-instance storage
    /// (reset with the batch); stable songID binding, never titles, so an
    /// unrelated same-title song never pollutes the count.
    var vaultQueueStoppedIDsForBatch: Set<String> = []
    /// P2 batch-cancel truth: per-batch set of songIDs whose queued operation
    /// was cancelled before execution (explicit queue cancel or Undo revocation).
    /// Per-instance storage (reset with the batch); stable songID binding, never
    /// titles. A cancelled item never completed, so the footer computes completed
    /// as total minus failures minus cancelled.
    var vaultQueueCanceledIDsForBatch: Set<String> = []
    /// P2 REQUEST-69: per-batch REQUEST counts. The ID sets above collapse
    /// repeats (cancel B, requeue B, cancel B keeps one songID) while every
    /// enqueue bumps `projectVaultQueueBatchCount`; footers must count requests,
    /// not distinct songs. Stable songIDs stay right for per-song messages.
    var vaultQueueStoppedRequestCountForBatch = 0
    var vaultQueueCanceledRequestCountForBatch = 0
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
    /// Bounded Done-retry delay. Production waits 60 seconds between attempts
    /// (at most 3); tests shorten it to exercise the same-auth retry path.
    var projectVaultDoneRetryDelay: Duration = .seconds(60)
    /// Per-song Project Vault card state prepared when catalog, snapshot, or
    /// settings inputs change. `projectVaultPresentation(for:)` is deliberately
    /// a dictionary lookup so list and board re-renders stay main-thread cheap.
    var projectVaultPresentationsBySongID: [String: ProjectVaultCardPresentation] = [:]
    /// Cached separately from the card map so a catalog/snapshot update can
    /// rebuild cards without reloading settings. Settings changes replace this
    /// context through `refreshProjectVaultPresentationContext()`.
    var projectVaultPresentationContext: ProjectVaultPresentationContext?
    var projectVaultSnapshotsByPath: [String: ProjectVaultRuntimeSnapshot] = [:]
    /// The latest runtime snapshot list is retained separately from the path lookup
    /// map so changing the archived-project visibility toggle can rebuild the catalog
    /// without another scan or Dropbox round trip.
    var projectVaultSnapshots: [ProjectVaultRuntimeSnapshot] = []
    var projectVaultRetryTasks: [String: Task<Void, Never>] = [:]
    var projectVaultRetryAttemptCounts: [String: Int] = [:]
    /// Done song IDs already postponed for non-retryable destination capacity.
    /// The automatic Done path must not re-enqueue them on a later snapshots
    /// refresh (launch recovery, settings changes, the recovery timer):
    /// without this, a full destination is re-attempted once per refresh after
    /// every rejection. Deliberate `archiveInProjectVault` calls bypass this
    /// gate; success, explicit confirmation/cancel/undo
    /// (`cancelDoneArchiveRetry`), cancel-all, and a newly persisted transfer
    /// release it.
    var projectVaultCapacityPostponedSongIDs: Set<String> = []
    var projectVaultRecoveryTask: Task<Void, Never>?
    var projectVaultRecoveryDeadline: Date?
    var projectVaultLastRecoveryAttemptAt: Date?
    var navigationCancellable: AnyCancellable?
    var intelligenceRefreshTask: Task<Void, Never>?
    var indexPersistTask: Task<Void, Never>?
    /// Reused search index rebuilt from the current shelf on each browse recompute.
    /// Avoids allocating a fresh `MusicSearchIndex` on every keystroke while still
    /// reflecting live metadata (titles/aliases) after catalog edits.
    var cachedSearchIndex = MusicSearchIndex()
    /// Security-scoped bookmark data keyed by `bookmarkKey(for:)` (canonical root
    /// path); persisted with the roots and re-resolved in `loadRootsFromSettings()`.
    var scanRootBookmarks: [String: Data] = [:]
    /// Keeps security-scoped access alive for bookmarked roots while the model lives.
    var securityScopedRootAccesses: [SecurityScopedRootAccess] = []
    public var requestConverterHandoff: ((URL) -> Void)?
    var statusBaseMessage: String?
    var persistenceWarningMessage: String?
    /// Background archive scans must not replace a newer, user-facing Project Vault
    /// operation status. Any non-Vault status update releases this ownership.
    var projectVaultOwnsStatus = false

    // MARK: - Computed

    var searchResultCountText: String? {
        guard isSearching else { return nil }
        return "\(filteredSongs.count) \(filteredSongs.count == 1 ? "result" : "results")"
    }

    var searchQuery: String {
        get { searchInput.query }
        set { searchInput.query = newValue }
    }

    public var pendingProjectVaultOperationCount: Int { projectVaultBusySongIDs.count }

    var showsSidebarMorePanel: Bool {
        !roots.isEmpty
    }

    // MARK: - Init

    public convenience init(
        context: ToolContext,
        archiveIndexStore: (any ArchiveIndexStoring)? = nil,
        songMetadataStore: (any SongUserMetadataStoring)? = nil,
        archiveRootWatcher: (any ArchiveRootWatching)? = nil,
        collaboratorStore: (any CollaboratorStoring)? = nil,
        browseSearchDebounceNanoseconds: UInt64 = 200_000_000,
        runtime: MusicHubRuntimeEnvironment = .current
    ) {
        self.init(
            context: context,
            archiveIndexStore: archiveIndexStore,
            songMetadataStore: songMetadataStore,
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
        archiveRootWatcher: (any ArchiveRootWatching)? = nil,
        collaboratorStore: (any CollaboratorStoring)? = nil,
        projectVaultRuntime: (any ProjectVaultOperating)? = nil,
        projectCatalogStore: SQLiteProjectCatalogStore? = nil,
        browseSearchDebounceNanoseconds: UInt64 = 200_000_000,
        runtime: MusicHubRuntimeEnvironment = .current,
        bookmarkProvider: any SecurityScopedBookmarkProviding = FoundationSecurityScopedBookmarks(),
        scanOverride: (([URL]) async throws -> ScanResult)?,
        incrementalRescanHold: (() async -> Void)? = nil
    ) {
        self.settingsStore = context.settingsStore
        self.router = context.router
        self.diagnostics = context.diagnostics
        self.fileActions = context.fileActions
        self.jobStatusCenter = context.jobStatusCenter
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
            collaboratorStore: collaboratorStore,
            diagnostics: context.diagnostics,
            settingsStore: context.settingsStore
        )
        self.browseRefreshDriver = ArchiveBrowseRefreshDriver(debounceNanoseconds: browseSearchDebounceNanoseconds)
        let dryRunOnly = runtime.dryRunOpen
        self.opener = MusicItemOpener(
            workspace: dryRunOnly ? nil : AppKitWorkspaceOpener(),
            log: { [diagnostics] message in
                diagnostics.log(.info, message)
            }
        )
        workflowUndoTarget.viewModel = self
        loadRootsFromSettings()
        attachNavigationHistory(context.navigationHistory)
        refreshProjectVaultPresentationContext(notifyWhenChanged: false)
        loadCollaborators()
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

    deinit {
        projectVaultAuthCaptureTask?.cancel()
        projectVaultRecoveryTask?.cancel()
        projectVaultQueueTask?.cancel()
    }

    // MARK: - Helpers

    /// Mirrors scan and Vault-transfer activity into the shell job status center;
    /// driven by the `isScanning` / `projectVaultActiveOperation` observers.
    private func publishShellJobStatus() {
        if isScanning {
            jobStatusCenter.setExtraJob(
                sourceID: ShellJobExtraSourceID.archiveScan,
                status: ShellJobStatus(
                    id: ShellJobExtraSourceID.archiveScan,
                    title: ShellJobStatusCopy.scanningArchive,
                    cancelActionID: ShellJobExtraSourceID.archiveScan
                ),
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
                status: ShellJobStatus(
                    id: ShellJobExtraSourceID.vaultTransfer,
                    title: operation.songName,
                    cancelActionID: ShellJobExtraSourceID.vaultTransfer,
                    activityVerb: "Transferring"
                ),
                cancel: { [weak self] in
                    Task { @MainActor in
                        self?.requestStopActiveProjectVaultTransfer()
                    }
                }
            )
        } else {
            jobStatusCenter.setExtraJob(sourceID: ShellJobExtraSourceID.vaultTransfer, status: nil)
        }
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
