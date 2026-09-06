import AppCore
import Foundation
import NikoMusicCore

/// Archive shell view model. Browse, scan, metadata, and exports live in `ArchiveBrowserViewModel+*.swift`
/// extensions; mixdown/CPR analysis is delegated to dedicated coordinators.
@MainActor
public final class ArchiveBrowserViewModel: ObservableObject {
    var rootGeneration: UInt64 = 0
    lazy var scanOrchestrator = ArchiveScanOrchestrator(host: self)

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
            rebuildProjectVaultPresentationCache(for: newValue, notifyWhenChanged: false)
        }
    }
    /// Songs discovered by the configured active/scan roots. Project Vault archive
    /// generations are projected into `songs` only when the user opts into them, so
    /// toggling that view never loses the clean scan baseline.
    var scannedSongs: [Song] = []
    @Published var filteredSongs: [Song] = []
    @Published var searchMatchSummaries: [String: String] = [:]
    @Published var skippedSearchMatches: [SkippedEntrySearchResult] = []
    let searchInput = ArchiveSearchInput()
    var searchQuery: String {
        get { searchInput.query }
        set { searchInput.query = newValue }
    }
    @Published var selectedShelf: ArchiveSmartShelf = .allSongs
    @Published var selectedCollaboratorID: String?
    @Published var selectedSong: Song?
    /// Song-detail "Details" disclosure state — hoisted so the browser-level "d"
    /// keyboard shortcut can toggle it.
    @Published var songDetailsExpanded = false
    @Published var isScanning = false
    @Published var statusMessage: String?
    @Published var scanDiagnostics: ArchiveScanDiagnostics?
    @Published var lastDryRunLog: String?
    @Published var lastDiagnosticsExportPath: String?
    @Published var lastIndexExportPath: String?
    @Published var needsFirstRunOnboarding = false
    @Published var collaborators: [Collaborator] = []
    @Published var showHiddenSongs = false
    @Published var sortMode: ArchiveBrowseSortMode = .recentCPR
    @Published var browseFilter: ArchiveBrowseFilter = []
    @Published var pendingCollaboratorSuggestions: [CollaboratorSuggestion] = []
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
    public var pendingProjectVaultOperationCount: Int { projectVaultBusySongIDs.count }
    @Published var projectVaultBusySongIDs: Set<String> = []
    @Published var projectVaultPendingOperations: [ProjectVaultQueuedOperation] = []
    @Published var projectVaultActiveOperation: ProjectVaultQueuedOperation?
    @Published var projectVaultOperationMessages: [String: String] = [:]
    var projectVaultQueueTask: Task<Void, Never>?
    var projectVaultQueueFailures: [String] = []
    var projectVaultQueueBatchCount = 0
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
    var projectVaultRecoveryTask: Task<Void, Never>?
    var projectVaultRecoveryDeadline: Date?
    var projectVaultLastRecoveryAttemptAt: Date?
    /// Archive page layout: the board is home, opening a card goes to
    /// fullscreen detail, and the classic sidebar+detail list stays reachable.
    enum ArchiveViewMode {
        case board
        case boardDetail
        case list
        case analytics
    }

    @Published var viewMode: ArchiveViewMode = .board
    @Published var analyticsSnapshot: ArchiveAnalyticsSnapshot?

    let catalog: ArchiveCatalogCoordinator
    let browseRefreshDriver: ArchiveBrowseRefreshDriver
    let mixdownAnalysis = ArchiveMixdownAnalysisCoordinator()
    let cprPlugins = ArchiveCPRPluginCoordinator()
    var intelligenceRefreshTask: Task<Void, Never>?
    var indexPersistTask: Task<Void, Never>?
    /// Reused search index rebuilt from the current shelf on each browse recompute.
    /// Avoids allocating a fresh `MusicSearchIndex` on every keystroke while still
    /// reflecting live metadata (titles/aliases) after catalog edits.
    var cachedSearchIndex = MusicSearchIndex()
    let opener: MusicItemOpener
    let pathSafety = PathSafety()
    let fileActions: any FileActions
    let settingsStore: SettingsStore
    let diagnostics: Diagnostics
    private let collaboratorStore: (any CollaboratorStoring)?
    let archiveRootWatcher: (any ArchiveRootWatching)?
    let runtime: MusicHubRuntimeEnvironment
    let scanOverride: (([URL]) async throws -> ScanResult)?

    deinit {
        projectVaultRecoveryTask?.cancel()
        projectVaultQueueTask?.cancel()
    }
    let projectVaultRuntime: (any ProjectVaultOperating)?
    public var requestConverterHandoff: ((URL) -> Void)?
    var statusBaseMessage: String?
    var persistenceWarningMessage: String?
    /// Background archive scans must not replace a newer, user-facing Project Vault
    /// operation status. Any non-Vault status update releases this ownership.
    var projectVaultOwnsStatus = false
    private var securityScopedRootAccesses: [SecurityScopedRootAccess] = []

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
        browseSearchDebounceNanoseconds: UInt64 = 200_000_000,
        runtime: MusicHubRuntimeEnvironment = .current,
        scanOverride: (([URL]) async throws -> ScanResult)?
    ) {
        self.settingsStore = context.settingsStore
        self.diagnostics = context.diagnostics
        self.fileActions = context.fileActions
        self.collaboratorStore = collaboratorStore
        self.archiveRootWatcher = archiveRootWatcher
        self.runtime = runtime
        self.projectVaultRuntime = projectVaultRuntime
        self.scanOverride = scanOverride
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
        loadRootsFromSettings()
        refreshProjectVaultPresentationContext(notifyWhenChanged: false)
        loadCollaborators()
        refreshFirstRunState()
        restartArchiveRootWatching()
        loadCachedIndexIfAvailable()
        Task {
            await projectVaultRuntime?.recoverAtLaunch()
            await refreshProjectVaultSnapshots()
        }
        if archiveRootWatcher != nil, !roots.isEmpty, !runtime.usesFixtureRoot {
            setStatusMessage("Scanning archive...")
            Task { await scanInBackground() }
        }
    }

    func loadRootsFromSettings() {
        if let fixtureRoot = runtime.fixtureRootURL {
            roots = [fixtureRoot]
            return
        }
        do {
            let settings = try settingsStore.loadSettings()
            let resolver = FoundationSecurityScopedBookmarks()
            securityScopedRootAccesses.removeAll()
            let loadedRoots = settings.effectiveScanRoots
                .filter { root in
                    !(settings.vault.isEnabled && root.id == settings.vault.archiveRootID)
                }
                .compactMap { root -> URL? in
                do {
                    let resolved = try root.resolvedURL(using: resolver)
                    if root.securityScopedBookmark != nil {
                        securityScopedRootAccesses.append(SecurityScopedRootAccess(url: resolved))
                    }
                    return resolved
                } catch {
                    recordPersistenceWarning("Archive root access could not be restored: \(root.displayName).")
                    diagnostics.log(.error, "Archive root bookmark resolution failed: \(error)")
                    return nil
                }
                }
            roots = ArchiveRootDisplayPolicy.storedRoots(from: loadedRoots)
        } catch {
            recordPersistenceWarning("Archive settings could not be loaded: \(error.localizedDescription)")
            diagnostics.log(.error, "Archive settings load failed: \(error)")
        }
        applyBootstrapRootWhenEmpty()
        refreshFirstRunState()
    }

    func refreshFirstRunState() {
        if runtime.usesFixtureRoot {
            needsFirstRunOnboarding = false
            return
        }
        if !roots.isEmpty {
            needsFirstRunOnboarding = false
            return
        }
        let completed = (try? settingsStore.loadSettings())?.archiveOnboardingCompleted ?? false
        let hasDevBootstrap =
            runtime.usesIsolatedSettingsSuite
            ? false
            : ArchiveDefaultRootPolicy.bootstrapRoot(runtime: runtime) != nil
        needsFirstRunOnboarding = !completed && !hasDevBootstrap
    }

    func completeArchiveOnboarding() {
        do {
            try settingsStore.updateSettings { settings in
                settings.archiveOnboardingCompleted = true
            }
        } catch {
            recordPersistenceWarning("Archive settings could not be saved: \(error.localizedDescription)")
            diagnostics.log(.error, "Archive onboarding save failed: \(error)")
        }
        needsFirstRunOnboarding = false
    }

    var newSongDraftRoot: URL {
        let outputFolder = (try? settingsStore.loadSettings().outputFolder.url)
            ?? StoredFolderLocation.defaultOutputFolder
        return outputFolder.appendingPathComponent("New Song Drafts", isDirectory: true)
    }

    /// Archive roots plus the configured output folder (new-song drafts live there).
    func allowedOpenRoots(for song: Song? = nil, includingURL url: URL? = nil) -> [URL] {
        var allowed = roots.map(\.standardizedFileURL)
        let settings = try? settingsStore.loadSettings()
        let outputFolder = settings?.outputFolder.url
            ?? StoredFolderLocation.defaultOutputFolder
        let standardizedOutput = outputFolder.standardizedFileURL
        if !allowed.contains(where: { $0.path == standardizedOutput.path }) {
            allowed.append(standardizedOutput)
        }
        if let song, !blocksGenericProjectVaultFileActions(for: song) {
            appendSongFolderRoot(song.folderPath, to: &allowed)
        } else if let url,
                  let song = songs.first(where: { catalogSong in
                      let folderPath = catalogSong.folderPath.standardizedFileURL.path
                      let candidatePath = url.standardizedFileURL.path
                      return candidatePath == folderPath || candidatePath.hasPrefix(folderPath + "/")
                  }),
                  !blocksGenericProjectVaultFileActions(for: song) {
            appendSongFolderRoot(song.folderPath, to: &allowed)
        }
        return allowed
    }

    func appendSongFolderRoot(_ folderPath: URL, to allowed: inout [URL]) {
        let songFolder = folderPath.standardizedFileURL
        if !allowed.contains(where: { songFolder.path == $0.path || songFolder.path.hasPrefix($0.path + "/") }) {
            allowed.append(songFolder)
        }
    }

    func applyBootstrapRootWhenEmpty() {
        if runtime.usesIsolatedSettingsSuite {
            return
        }
        guard roots.isEmpty, let bootstrap = ArchiveDefaultRootPolicy.bootstrapRoot(runtime: runtime) else { return }
        roots = [bootstrap]
    }

    func persistRoots() {
        let snapshot = roots
        do {
            try settingsStore.updateSettings { settings in
                settings.archiveRoots = snapshot.map { StoredArchiveRoot(path: $0.path) }
            }
        } catch {
            recordPersistenceWarning("Archive settings could not be saved: \(error.localizedDescription)")
            diagnostics.log(.error, "Archive roots save failed: \(error)")
        }
    }

    public func addRoot(_ url: URL) {
        addRoots([url])
    }

    func addRoots(_ urls: [URL]) {
        var changed = false
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !roots.contains(where: { $0.path == standardized.path }) else { continue }
            roots.append(standardized)
            changed = true
        }
        if changed {
            completeArchiveOnboarding()
            persistRoots()
            restartArchiveRootWatching()
            refreshFirstRunState()
            setStatusMessage("Scanning archive...")
            Task { await scanInBackground() }
        }
    }

    public func removeRoot(_ url: URL) {
        let before = roots
        let standardizedPath = url.standardizedFileURL.path
        roots.removeAll { $0.standardizedFileURL.path == standardizedPath }
        guard before.standardizedArchivePaths != roots.standardizedArchivePaths else { return }
        clearRootBoundArchiveState(
            statusMessage: roots.isEmpty ? nil : "Archive roots changed. Scan to refresh."
        )
        persistRoots()
        restartArchiveRootWatching()
        refreshFirstRunState()
    }

    func toggleBrowseFilter(_ filter: ArchiveBrowseFilter) {
        mutateBrowseInputs {
            var next = browseFilter
            if next.contains(filter) {
                next.remove(filter)
            } else {
                next.insert(filter)
            }
            browseFilter = next
        }
    }

    func toggleShowHiddenSongs() {
        mutateBrowseInputs {
            showHiddenSongs.toggle()
        }
    }

    func setSortMode(_ mode: ArchiveBrowseSortMode) {
        mutateBrowseInputs {
            sortMode = mode
        }
    }

    func setSelectedCollaboratorID(_ id: String?) {
        mutateBrowseInputs {
            selectedCollaboratorID = id
        }
    }

    func selectSong(_ song: Song) {
        let previousID = selectedSong?.id
        // Stop list/detail audio when changing songs so detail never fights a row player.
        if previousID != song.id {
            ArchivePlaybackCoordinator.shared.stopAllPlayback()
        }
        selectedSong = song
        // Keep the first viewport calm when changing songs (ARCH-07).
        if songDetailsExpanded {
            songDetailsExpanded = false
        }
        if pluginsSectionExpanded {
            pluginsSectionExpanded = false
        }
        // Opening from the board goes to fullscreen detail; list stays list.
        if viewMode == .board {
            viewMode = .boardDetail
        }
        refreshMixdownAnalysis(for: song)
    }

    /// Opens the analytics page over the board with a fresh snapshot built
    /// from the live catalog and the recorded status history.
    func showAnalytics() {
        refreshAnalytics()
        viewMode = .analytics
    }

    func refreshAnalytics() {
        let history = (catalog.songMetadataStore as? WorkflowStatusHistoryReading)
            .flatMap { try? $0.loadAllStatusHistory() } ?? []
        analyticsSnapshot = ArchiveAnalyticsProjection.snapshot(songs: songs, history: history)
    }

    /// Board single-click: highlight the card and load it into the board's
    /// player bar without leaving the board. Double-click uses `selectSong`.
    func selectSongOnBoard(_ song: Song) {
        guard selectedSong?.id != song.id else { return }
        // One audible source at a time — same rule as list/detail selection.
        ArchivePlaybackCoordinator.shared.stopAllPlayback()
        selectedSong = song
        if songDetailsExpanded {
            songDetailsExpanded = false
        }
        if pluginsSectionExpanded {
            pluginsSectionExpanded = false
        }
    }

    /// Keeps `selectedSong` in sync with the live catalog and current browse results.
    /// - Clears selection when the song disappeared from the catalog.
    /// - Refreshes the snapshot after scan/metadata so detail never shows stale CPR/previews.
    /// - Clears selection when the song is filtered out of the current browse list.
    func reconcileSelectedSong(requireVisibleInFilteredList: Bool = true) {
        guard let current = selectedSong else { return }
        guard let fresh = songs.first(where: { $0.id == current.id }) else {
            clearSelection(stopPlayback: true)
            return
        }
        if requireVisibleInFilteredList, !filteredSongs.contains(where: { $0.id == fresh.id }) {
            clearSelection(stopPlayback: true)
            return
        }
        if fresh != current {
            selectedSong = fresh
        }
    }

    func clearSelection(stopPlayback: Bool) {
        if stopPlayback {
            ArchivePlaybackCoordinator.shared.stopAllPlayback()
        }
        selectedSong = nil
        songDetailsExpanded = false
        pluginsSectionExpanded = false
    }

    func healthReport() -> ArchiveHealthReport {
        ArchiveHealthReport(songs: songs, includeHidden: showHiddenSongs)
    }

    var showsSidebarMorePanel: Bool {
        !roots.isEmpty
    }

    var sidebarHealthContext: ArchiveSidebarHealthContext {
        let report = healthReport()
        return ArchiveSidebarHealthContext.make(
            report: report,
            skippedEntryCount: scanDiagnostics?.skippedEntries.count ?? 0
        )
    }

    func refreshIntelligence() {
        scheduleIntelligenceRefresh(immediate: false)
    }

    /// Immediate intelligence refresh (collaborator upsert, tests). Prefer the debounced path
    /// for scan/catalog churn so rapid updates coalesce before rebuilding the summary.
    func refreshIntelligenceNow() {
        scheduleIntelligenceRefresh(immediate: true)
    }

    func scheduleIntelligenceRefresh(immediate: Bool) {
        intelligenceRefreshTask?.cancel()
        let snapshotSongs = songs
        let snapshotCollaborators = collaborators
        intelligenceRefreshTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
            }
            let suggestions = ArchiveIntelligence.collaboratorSuggestions(
                songs: snapshotSongs,
                collaborators: snapshotCollaborators
            )
            let duplicates = ArchiveIntelligence.duplicateSongHints(songs: snapshotSongs)
            // The live panel renders only the summary counts. Keeping this at a
            // zero orphan-path budget avoids a recursive filesystem walk and makes
            // the debounced task its complete, cancellable refresh lifecycle.
            let missing = ArchiveIntelligence.missingAudioReport(
                songs: snapshotSongs,
                maximumRetainedOrphanAudioPaths: 0
            )
            guard let self, !Task.isCancelled else { return }
            self.pendingCollaboratorSuggestions = suggestions
            self.duplicateSongHints = duplicates
            self.missingAudioReport = missing
        }
    }

    func setStatusMessage(_ message: String?) {
        projectVaultOwnsStatus = false
        statusBaseMessage = message
        statusMessage = combinedStatusMessage(base: message)
    }

    func setProjectVaultStatusMessage(_ message: String?) {
        projectVaultOwnsStatus = true
        statusBaseMessage = message
        statusMessage = combinedStatusMessage(base: message)
    }

    func setBackgroundStatusMessage(_ message: String?) {
        guard !projectVaultOwnsStatus else { return }
        setStatusMessage(message)
    }

    func recordPersistenceWarning(_ warning: String) {
        persistenceWarningMessage = warning
        statusMessage = combinedStatusMessage(base: statusBaseMessage)
    }

    func combinedStatusMessage(base: String?) -> String? {
        guard let persistenceWarningMessage else { return base }
        guard let base, !base.isEmpty else { return persistenceWarningMessage }
        return "\(base) \(persistenceWarningMessage)"
    }

    func acceptCollaboratorSuggestion(_ suggestion: CollaboratorSuggestion) {
        guard let song = songs.first(where: { $0.id == suggestion.songID }) else { return }
        var ids = song.collaboratorIDs
        guard !ids.contains(suggestion.suggestedCollaboratorID) else { return }
        ids.append(suggestion.suggestedCollaboratorID)
        assignCollaborators(to: song, collaboratorIDs: ids)
        pendingCollaboratorSuggestions.removeAll { $0.id == suggestion.id }
    }

    func dismissCollaboratorSuggestion(_ suggestion: CollaboratorSuggestion) {
        pendingCollaboratorSuggestions.removeAll { $0.id == suggestion.id }
    }

    func loadCollaborators() {
        guard let collaboratorStore else { return }
        do {
            collaborators = try collaboratorStore.loadAll()
        } catch {
            diagnostics.log(.error, "Collaborator load failed: \(error)")
            collaborators = []
        }
    }

    func upsertCollaborator(name: String) -> Collaborator? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let collaboratorStore else { return nil }
        let collaborator = Collaborator(displayName: trimmed)
        do {
            try collaboratorStore.upsert(collaborator)
            loadCollaborators()
            refreshIntelligenceNow()
            return collaborator
        } catch {
            diagnostics.log(.error, "Collaborator save failed: \(error)")
            return nil
        }
    }

    func bpmEstimate(for song: Song) -> MixdownBPMEstimate? {
        mixdownAnalysis.bpmEstimate(for: song, in: mixdownBPMBySongID)
    }

    func keyEstimate(for song: Song) -> MixdownKeyEstimate? {
        mixdownAnalysis.keyEstimate(for: song, in: mixdownKeyBySongID)
    }

    func cprPluginSummary(for song: Song) -> CPRPluginSummary? {
        cprPlugins.summary(for: song, in: cprPluginSummaryByCPRPath)
    }

    func refreshMixdownAnalysis(for song: Song) {
        mixdownAnalysis.refresh(
            for: song,
            bpmCache: mixdownBPMBySongID,
            keyCache: mixdownKeyBySongID,
            isStillSelected: { [weak self] songID, cacheKey in
                guard let self, self.selectedSong?.id == songID else { return false }
                guard let currentSong = self.selectedSong,
                      currentSong.id == songID,
                      self.mixdownAnalysisCacheKey(for: currentSong) == cacheKey else { return false }
                return true
            },
            apply: { [weak self] cacheKey, bpmEstimate, keyEstimate in
                guard let self else { return }
                if let bpmEstimate, self.mixdownBPMBySongID[cacheKey] == nil {
                    self.mixdownBPMBySongID[cacheKey] = bpmEstimate
                }
                if let keyEstimate, self.mixdownKeyBySongID[cacheKey] == nil {
                    self.mixdownKeyBySongID[cacheKey] = keyEstimate
                }
            }
        )
    }

    /// BPM/key must key off the active preview file, not just song folder id.
    func mixdownAnalysisCacheKey(for song: Song) -> String? {
        ArchiveMixdownAnalysisCoordinator.cacheKey(for: song)
    }

    func invalidateMixdownAnalysis(for songID: String) {
        mixdownAnalysis.cancel()
        ArchiveMixdownAnalysisCoordinator.invalidate(
            for: songID,
            bpmCache: &mixdownBPMBySongID,
            keyCache: &mixdownKeyBySongID
        )
    }

    func invalidateCPRPluginSummary(for path: String) {
        cprPlugins.cancel()
        ArchiveCPRPluginCoordinator.invalidate(path: path, cache: &cprPluginSummaryByCPRPath)
    }

    func refreshCPRPluginSummary(for song: Song) {
        cprPlugins.refresh(
            for: song,
            cache: cprPluginSummaryByCPRPath,
            isStillSelected: { [weak self] songID in
                self?.selectedSong?.id == songID
            },
            apply: { [weak self] path, summary in
                self?.cprPluginSummaryByCPRPath[path] = summary
            }
        )
    }

    func convertMainPreview(for song: Song) {
        guard let id = song.mainPreviewCandidateID,
              let url = song.previewCandidates.first(where: { $0.id == id })?.filePath else {
            return
        }
        requestConverterHandoff?(url)
    }

    func chooseTemplateFolder() -> URL? {
        fileActions.chooseDirectory(prompt: "Choose Cubase or Ableton template folder")
    }
}
