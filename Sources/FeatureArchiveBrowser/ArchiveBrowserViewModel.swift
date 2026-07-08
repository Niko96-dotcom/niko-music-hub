import AppCore
import Foundation
import NikoMusicCore

/// Archive shell view model. Browse, scan, metadata, and exports are split by MARK in this file
/// so catalog/browse invariants stay ``private`` without cross-file extension leaks.
@MainActor
public final class ArchiveBrowserViewModel: ObservableObject {
    var rootGeneration: UInt64 = 0
    private lazy var scanOrchestrator = ArchiveScanOrchestrator(host: self)

    @Published public var roots: [URL] = [] {
        didSet {
            guard oldValue.standardizedArchivePaths != roots.standardizedArchivePaths else { return }
            invalidateActiveScanForRootChange()
        }
    }
    @Published private(set) var songs: [Song] = []
    @Published private(set) var filteredSongs: [Song] = []
    @Published private(set) var searchMatchSummaries: [String: String] = [:]
    @Published private(set) var skippedSearchMatches: [SkippedEntrySearchResult] = []
    @Published private(set) var searchQuery: String = ""
    @Published private(set) var selectedShelf: ArchiveSmartShelf = .allSongs
    @Published private(set) var selectedCollaboratorID: String?
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
    @Published private(set) var showHiddenSongs = false
    @Published private(set) var sortMode: ArchiveBrowseSortMode = .recentCPR
    @Published private(set) var browseFilter: ArchiveBrowseFilter = []
    @Published var pendingCollaboratorSuggestions: [CollaboratorSuggestion] = []
    @Published var duplicateSongHints: [DuplicateSongHint] = []
    @Published var missingAudioReport: MissingAudioReport?
    @Published var mixdownBPMBySongID: [String: MixdownBPMEstimate] = [:]
    @Published private(set) var mixdownKeyBySongID: [String: MixdownKeyEstimate] = [:]
    @Published private(set) var cprPluginSummaryByCPRPath: [String: CPRPluginSummary] = [:]
    @Published var pluginsSectionExpanded = false

    let catalog: ArchiveCatalogCoordinator
    private let browseRefreshDriver: ArchiveBrowseRefreshDriver
    private var mixdownAnalysisTask: Task<Void, Never>?
    private var pluginLoadTask: Task<Void, Never>?
    private var intelligenceRefreshTask: Task<Void, Never>?
    private var indexPersistTask: Task<Void, Never>?
    /// Reused search index rebuilt from the current shelf on each browse recompute.
    /// Avoids allocating a fresh `MusicSearchIndex` on every keystroke while still
    /// reflecting live metadata (titles/aliases) after catalog edits.
    private var cachedSearchIndex = MusicSearchIndex()
    private let opener: MusicItemOpener
    private let fileActions: any FileActions
    private let settingsStore: SettingsStore
    let diagnostics: Diagnostics
    private let collaboratorStore: (any CollaboratorStoring)?
    let archiveRootWatcher: (any ArchiveRootWatching)?
    private let runtime: MusicHubRuntimeEnvironment
    let scanOverride: (([URL]) async throws -> ScanResult)?
    public var requestConverterHandoff: ((URL) -> Void)?
    private var statusBaseMessage: String?
    private var persistenceWarningMessage: String?

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
        loadCollaborators()
        refreshFirstRunState()
        restartArchiveRootWatching()
        loadCachedIndexIfAvailable()
        if archiveRootWatcher != nil, !roots.isEmpty, !runtime.usesFixtureRoot {
            setStatusMessage("Scanning archive...")
            Task { await scan() }
        }
    }

    func loadRootsFromSettings() {
        if let fixtureRoot = runtime.fixtureRootURL {
            roots = [fixtureRoot]
            return
        }
        do {
            let settings = try settingsStore.loadSettings()
            let loadedRoots = settings.archiveRoots.map(\.url)
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

    private func applyBootstrapRootWhenEmpty() {
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
            Task { await scan() }
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
        songDetailsExpanded = false
        pluginsSectionExpanded = false
        refreshMixdownAnalysis(for: song)
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
    /// for scan/catalog churn so FS walks don't stall the main actor after every mutate.
    func refreshIntelligenceNow() {
        scheduleIntelligenceRefresh(immediate: true)
    }

    private func scheduleIntelligenceRefresh(immediate: Bool) {
        intelligenceRefreshTask?.cancel()
        let snapshotSongs = songs
        let snapshotCollaborators = collaborators
        intelligenceRefreshTask = Task { @MainActor [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
            }
            let suggestions = ArchiveIntelligence.collaboratorSuggestions(
                songs: snapshotSongs,
                collaborators: snapshotCollaborators
            )
            let duplicates = ArchiveIntelligence.duplicateSongHints(songs: snapshotSongs)
            let missing = await Task.detached(priority: .utility) {
                ArchiveIntelligence.missingAudioReport(songs: snapshotSongs)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.pendingCollaboratorSuggestions = suggestions
            self.duplicateSongHints = duplicates
            self.missingAudioReport = missing
        }
    }

    func setStatusMessage(_ message: String?) {
        statusBaseMessage = message
        statusMessage = combinedStatusMessage(base: message)
    }

    private func recordPersistenceWarning(_ warning: String) {
        persistenceWarningMessage = warning
        statusMessage = combinedStatusMessage(base: statusBaseMessage)
    }

    private func combinedStatusMessage(base: String?) -> String? {
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

    func refreshBPMEstimate(for song: Song) {
        refreshMixdownAnalysis(for: song)
    }

    func bpmEstimate(for song: Song) -> MixdownBPMEstimate? {
        guard let key = mixdownAnalysisCacheKey(for: song) else { return nil }
        return mixdownBPMBySongID[key]
    }

    func keyEstimate(for song: Song) -> MixdownKeyEstimate? {
        guard let key = mixdownAnalysisCacheKey(for: song) else { return nil }
        return mixdownKeyBySongID[key]
    }

    func cprPluginSummary(for song: Song) -> CPRPluginSummary? {
        guard let cpr = song.effectiveLatestCPR else { return nil }
        return cprPluginSummaryByCPRPath[cpr.filePath.standardizedFileURL.path]
    }

    func refreshKeyEstimate(for song: Song) {
        refreshMixdownAnalysis(for: song)
    }

    func refreshMixdownAnalysis(for song: Song) {
        mixdownAnalysisTask?.cancel()
        guard let cacheKey = mixdownAnalysisCacheKey(for: song) else { return }
        let needsBPM = mixdownBPMBySongID[cacheKey] == nil
        let needsKey = mixdownKeyBySongID[cacheKey] == nil
        guard needsBPM || needsKey else { return }
        let songID = song.id
        let url = song.previewCandidates.first(where: { $0.id == song.mainPreviewCandidateID })?.filePath
        guard let url else { return }
        mixdownAnalysisTask = Task {
            let bpmEstimate: MixdownBPMEstimate?
            let keyEstimate: MixdownKeyEstimate?
            if needsBPM, needsKey {
                async let bpm = Task.detached(priority: .utility) {
                    MixdownBPMEstimator.estimate(url: url)
                }.value
                async let key = Task.detached(priority: .utility) {
                    MixdownKeyEstimator.estimate(url: url)
                }.value
                bpmEstimate = await bpm
                keyEstimate = await key
            } else if needsBPM {
                bpmEstimate = await Task.detached(priority: .utility) {
                    MixdownBPMEstimator.estimate(url: url)
                }.value
                keyEstimate = nil
            } else {
                bpmEstimate = nil
                keyEstimate = await Task.detached(priority: .utility) {
                    MixdownKeyEstimator.estimate(url: url)
                }.value
            }
            guard !Task.isCancelled, selectedSong?.id == songID else { return }
            if needsBPM, let bpmEstimate, mixdownBPMBySongID[cacheKey] == nil {
                mixdownBPMBySongID[cacheKey] = bpmEstimate
            }
            if needsKey, let keyEstimate, mixdownKeyBySongID[cacheKey] == nil {
                mixdownKeyBySongID[cacheKey] = keyEstimate
            }
        }
    }

    /// BPM/key must key off the active preview file, not just song folder id.
    private func mixdownAnalysisCacheKey(for song: Song) -> String? {
        guard let previewID = song.mainPreviewCandidateID else { return nil }
        return "\(song.id)|\(previewID)"
    }

    private func invalidateMixdownAnalysis(for songID: String) {
        mixdownBPMBySongID = mixdownBPMBySongID.filter { !$0.key.hasPrefix("\(songID)|") }
        mixdownKeyBySongID = mixdownKeyBySongID.filter { !$0.key.hasPrefix("\(songID)|") }
    }

    func refreshCPRPluginSummary(for song: Song) {
        pluginLoadTask?.cancel()
        guard let cpr = song.effectiveLatestCPR else { return }
        let path = cpr.filePath.standardizedFileURL.path
        guard cprPluginSummaryByCPRPath[path] == nil else { return }
        let songID = song.id
        pluginLoadTask = Task {
            let summary = await Task.detached(priority: .utility) {
                CPRPluginSummaryService.loadPlugins(cprURL: cpr.filePath)
            }.value
            guard !Task.isCancelled, selectedSong?.id == songID else { return }
            cprPluginSummaryByCPRPath[path] = summary
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
        fileActions.chooseDirectory(prompt: "Choose Cubase template folder")
    }
}

// MARK: - Browse projection and refresh

extension ArchiveBrowserViewModel {
    private func applyBrowseChange(shouldRefreshIntelligence: Bool, _ updates: () -> Void) {
        browseRefreshDriver.cancelPendingDebounce()
        updates()
        recomputeBrowseResults()
        if shouldRefreshIntelligence {
            refreshIntelligence()
        }
    }

    /// Shelf, filter, sort, and collaborator browse inputs. Always recomputes browse projection immediately.
    /// For live search typing use ``setSearchQuery(_:immediate:)`` instead — routing search through here
    /// would recompute on every keystroke and defeat debounce.
    func mutateBrowseInputs(_ updates: () -> Void) {
        applyBrowseChange(shouldRefreshIntelligence: false, updates)
    }

    func mutateCatalog(_ updates: () -> Void) {
        applyBrowseChange(shouldRefreshIntelligence: true, updates)
    }

    /// Debounced browse entry point for search text. Writes `searchQuery` directly (not via
    /// ``mutateBrowseInputs``) and recomputes after debounce, or immediately when `immediate` is true.
    func setSearchQuery(_ query: String, immediate: Bool = false) {
        searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Clearing search should refresh the list immediately so the empty field never
        // sits on a stale narrowed result set for ~200ms.
        let shouldImmediate = immediate || trimmed.isEmpty
        if shouldImmediate {
            browseRefreshDriver.cancelPendingDebounce()
            recomputeBrowseResults()
        } else {
            browseRefreshDriver.scheduleDebouncedBrowseRecompute { [weak self] in
                self?.recomputeBrowseResults()
            }
        }
    }

    func selectShelf(_ shelf: ArchiveSmartShelf) {
        mutateBrowseInputs {
            selectedShelf = shelf
            if shelf == .byCollaborator, selectedCollaboratorID == nil {
                selectedCollaboratorID = collaborators.first?.id
            }
        }
    }

    func browseState() -> ArchiveBrowseState {
        ArchiveBrowseState(
            songs: songs,
            showHiddenSongs: showHiddenSongs,
            selectedShelf: selectedShelf,
            selectedCollaboratorID: selectedCollaboratorID,
            searchQuery: searchQuery,
            browseFilter: browseFilter,
            sortMode: sortMode,
            skippedScanEntries: scanDiagnostics?.skippedEntries ?? []
        )
    }

    func recomputeBrowseResults() {
        let state = browseState()
        let onShelf = ArchiveBrowseProjection.shelfSongs(from: state)
        // Always refresh songs in the index so title/alias edits are searchable immediately.
        // Rebuild is an array assign; the expensive work is `searchResults` when a query is active.
        cachedSearchIndex.rebuild(from: onShelf)

        let result = ArchiveBrowseProjection.project(state, searchIndex: cachedSearchIndex)
        filteredSongs = result.filteredSongs
        searchMatchSummaries = result.searchMatchSummaries
        skippedSearchMatches = result.skippedSearchMatches
        reconcileSelectedSong(requireVisibleInFilteredList: true)
    }
}

// MARK: - Scan and cache

extension ArchiveBrowserViewModel {
    func clearScanResults() {
        clearRootBoundArchiveState(statusMessage: nil)
    }

    func scan() async {
        await scanOrchestrator.scan()
    }

    func scanSync() {
        scanOrchestrator.scanSync()
    }

    private func invalidateActiveScanForRootChange() {
        rootGeneration &+= 1
        isScanning = false
        scanOrchestrator.invalidateForRootChange()
    }

    private func clearRootBoundArchiveState(statusMessage nextStatusMessage: String?) {
        browseRefreshDriver.cancelPendingDebounce()
        intelligenceRefreshTask?.cancel()
        indexPersistTask?.cancel()
        persistenceWarningMessage = nil
        scanOrchestrator.clearPendingPaths()
        ArchivePlaybackCoordinator.shared.stopAllPlayback()
        ArchiveMiniPlayerModel.clearMetadataCaches()
        WaveformPeakCache.shared.clear()
        songs = []
        filteredSongs = []
        searchMatchSummaries = [:]
        skippedSearchMatches = []
        searchQuery = ""
        selectedShelf = .allSongs
        selectedCollaboratorID = nil
        browseFilter = []
        showHiddenSongs = false
        sortMode = .recentCPR
        selectedSong = nil
        songDetailsExpanded = false
        pluginsSectionExpanded = false
        scanDiagnostics = nil
        pendingCollaboratorSuggestions = []
        duplicateSongHints = []
        missingAudioReport = nil
        mixdownBPMBySongID = [:]
        mixdownKeyBySongID = [:]
        cprPluginSummaryByCPRPath = [:]
        cachedSearchIndex = MusicSearchIndex()
        setStatusMessage(nextStatusMessage)
    }

    @discardableResult
    private func loadCachedIndexIfAvailable() -> Bool {
        let cached = catalog.loadCachedSongs(roots: roots, collaborators: collaborators)
        guard case .loaded(let songs, let scannedAt) = cached else {
            if case .failed(let warning) = cached {
                recordPersistenceWarning(warning)
            }
            return false
        }
        mutateCatalog {
            self.songs = songs
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let relative = formatter.localizedString(for: scannedAt, relativeTo: Date())
            setStatusMessage("Loaded \(songs.count) songs from cache (\(relative)). Scan to refresh.")
        }
        return true
    }

    func restartArchiveRootWatching() {
        scanOrchestrator.restartArchiveRootWatching()
    }
}

extension ArchiveBrowserViewModel: ArchiveScanHost {
    func applyCatalogScanUpdate(_ update: ArchiveCatalogCoordinator.CatalogScanApplyResult, roots: [URL]) {
        let previousPreviewBySongID = Dictionary(
            uniqueKeysWithValues: songs.compactMap { song -> (String, String)? in
                guard let previewID = song.mainPreviewCandidateID else { return nil }
                return (song.id, previewID)
            }
        )
        mutateCatalog {
            songs = update.songs
            scanDiagnostics = update.diagnostics
            setStatusMessage(update.statusMessage)
        }
        // Refresh or clear selection against the new catalog (keep if still present even when
        // filtered out — browse recompute will clear filtered-out selections next).
        reconcileSelectedSong(requireVisibleInFilteredList: false)
        for song in update.songs {
            if previousPreviewBySongID[song.id] != song.mainPreviewCandidateID {
                invalidateMixdownAnalysis(for: song.id)
            }
        }
        // Drop analysis for songs that disappeared.
        let remainingIDs = Set(update.songs.map(\.id))
        mixdownBPMBySongID = mixdownBPMBySongID.filter { entry in
            remainingIDs.contains(where: { entry.key.hasPrefix("\($0)|") })
        }
        mixdownKeyBySongID = mixdownKeyBySongID.filter { entry in
            remainingIDs.contains(where: { entry.key.hasPrefix("\($0)|") })
        }
        // Scan already writes a fresh index — cancel any pending metadata-edit persist.
        indexPersistTask?.cancel()
        if let warning = catalog.persistCachedIndex(roots: roots, songs: songs, scannedAt: update.scannedAt) {
            recordPersistenceWarning(warning)
        }
        if update.shouldPersistUserMetadata,
           let warning = catalog.persistUserMetadata(for: songs) {
            recordPersistenceWarning(warning)
        }
    }

    func applyScanFailure(_ error: Error) {
        mutateCatalog {
            scanDiagnostics = nil
            setStatusMessage("Scan failed: \(error.localizedDescription)")
        }
        diagnostics.log(.error, statusMessage ?? "scan failed")
    }
}

// MARK: - Metadata

extension ArchiveBrowserViewModel {
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

    func updateWorkflowStatus(for song: Song, status: ProjectWorkflowStatus?) {
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.workflowStatus = status
        }
    }

    func setManualMainPreview(for song: Song, candidateID: String) {
        guard songs.first(where: { $0.id == song.id })?.previewCandidates.contains(where: { $0.id == candidateID }) == true else {
            return
        }
        invalidateMixdownAnalysis(for: song.id)
        if let path = songs.first(where: { $0.id == song.id })?
            .previewCandidates.first(where: { $0.id == candidateID })?.filePath {
            ArchiveMiniPlayerModel.invalidateMetadataCaches(for: path)
        }
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.previewSelectionMode = .manual
            metadata.manualMainPreviewID = candidateID
        }
        if let updated = songs.first(where: { $0.id == song.id }) {
            refreshMixdownAnalysis(for: updated)
        }
    }

    func revertPreviewToAuto(for song: Song) {
        invalidateMixdownAnalysis(for: song.id)
        applyMetadataMerge(for: song, rankingRefresh: .previewAuto) { metadata, scanned in
            metadata.previewSelectionMode = .auto
            metadata.manualMainPreviewID = nil
            scanned.previewSelectionMode = .auto
        }
        if let updated = songs.first(where: { $0.id == song.id }) {
            refreshMixdownAnalysis(for: updated)
        }
    }

    func ignorePreviewCandidate(for song: Song, candidateID: String) {
        applyMetadataMerge(for: song) { metadata, scanned in
            if !metadata.ignoredPreviewCandidateIDs.contains(candidateID) {
                metadata.ignoredPreviewCandidateIDs.append(candidateID)
            }
            if metadata.manualMainPreviewID == candidateID {
                metadata.previewSelectionMode = .auto
                metadata.manualMainPreviewID = nil
            }
            if scanned.mainPreviewCandidateID == candidateID {
                scanned.previewSelectionMode = .auto
            }
        }
    }

    func setManualMainCPR(for song: Song, versionID: String) {
        guard songs.first(where: { $0.id == song.id })?.visibleProjectVersions.contains(where: { $0.id == versionID }) == true else {
            return
        }
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.cprSelectionMode = .manual
            metadata.manualMainCPRID = versionID
        }
    }

    func revertCPRToAuto(for song: Song) {
        applyMetadataMerge(for: song, rankingRefresh: .cprAuto) { metadata, scanned in
            metadata.cprSelectionMode = .auto
            metadata.manualMainCPRID = nil
            scanned.cprSelectionMode = .auto
            scanned.manualMainCPRID = nil
        }
    }

    func ignoreCPRVersion(for song: Song, versionID: String) {
        applyMetadataMerge(for: song) { metadata, _ in
            if !metadata.ignoredCPRVersionIDs.contains(versionID) {
                metadata.ignoredCPRVersionIDs.append(versionID)
            }
            if metadata.manualMainCPRID == versionID {
                metadata.cprSelectionMode = .auto
                metadata.manualMainCPRID = nil
            }
        }
    }

    func setSongHidden(_ song: Song, hidden: Bool) {
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.isIgnored = hidden
        }
        if hidden, selectedSong?.id == song.id {
            clearSelection(stopPlayback: true)
        }
    }

    func assignCollaborators(to song: Song, collaboratorIDs: [String]) {
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.collaboratorIDs = collaboratorIDs
        }
    }

    func createNewSong(request: NewSongRequest) throws -> Song {
        var created = try NewSongFolderCreator.create(request: request, protectedRoots: roots)
        created = catalog.mergeUserMetadata(into: [created], collaborators: collaborators).first ?? created
        mutateCatalog {
            var updatedSongs = songs
            if let index = updatedSongs.firstIndex(where: { $0.id == created.id }) {
                updatedSongs[index] = created
            } else {
                updatedSongs.append(created)
                updatedSongs.sort {
                    $0.effectiveDisplayTitle.localizedCaseInsensitiveCompare($1.effectiveDisplayTitle) == .orderedAscending
                }
            }
            songs = updatedSongs
        }
        if let warning = catalog.persistUserMetadata(for: [created]) {
            recordPersistenceWarning(warning)
        }
        if !roots.isEmpty {
            if let warning = catalog.persistCachedIndex(
                roots: roots,
                songs: songs,
                scannedAt: scanDiagnostics?.scannedAt ?? Date()
            ) {
                recordPersistenceWarning(warning)
            }
        }
        selectSong(created)
        if created.effectiveLatestCPR != nil {
            try openLatestCPR(for: created)
        } else {
            setStatusMessage(
                "Created draft \(created.originalFolderName). No CPR project file yet; folder is ready at \(created.folderPath.path)."
            )
        }
        return created
    }

    private func applyMetadataMerge(
        for song: Song,
        rankingRefresh: ArchiveSongMetadataEditor.RankingRefresh = .none,
        mutate: (inout SongUserMetadata, inout Song) -> Void
    ) {
        guard let merged = ArchiveSongMetadataEditor.mergedSongAfterEdit(
            for: song,
            in: songs,
            collaborators: collaborators,
            rankingRefresh: rankingRefresh,
            mutate: mutate
        ) else { return }
        commitSongMetadataUpdate(merged)
    }

    private func commitSongMetadataUpdate(_ updated: Song) {
        replaceSong(updated)
        if let warning = catalog.persistUserMetadata(for: [updated]) {
            recordPersistenceWarning(warning)
        }
        scheduleDebouncedIndexPersist()
    }

    /// Coalesce full-catalog JSON index writes while the user edits metadata.
    /// Reads live catalog state at fire time so a later scan cannot be overwritten by a stale snapshot.
    private func scheduleDebouncedIndexPersist() {
        guard !roots.isEmpty else { return }
        indexPersistTask?.cancel()
        indexPersistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            guard !self.roots.isEmpty else { return }
            if let warning = self.catalog.persistCachedIndex(
                roots: self.roots,
                songs: self.songs,
                scannedAt: self.scanDiagnostics?.scannedAt ?? Date()
            ) {
                self.recordPersistenceWarning(warning)
            }
        }
    }

    private func replaceSong(_ updated: Song) {
        mutateCatalog {
            if let index = songs.firstIndex(where: { $0.id == updated.id }) {
                var updatedSongs = songs
                updatedSongs[index] = updated
                songs = updatedSongs
            }
        }
        if selectedSong?.id == updated.id {
            selectedSong = updated
        }
    }

}

// MARK: - Exports and file actions

extension ArchiveBrowserViewModel {
    /// Runs an export action and surfaces failures on `statusMessage`.
    func performExport(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            setStatusMessage("Export failed: \(error.localizedDescription)")
        }
    }

    func exportIndexJSON() throws {
        let destination = try ArchiveExportPaths.stampedFileURL(
            subdirectory: "niko-music-hub-exports",
            namePrefix: "archive-index",
            nameSuffix: ".json"
        )
        let data = try ArchiveIndexExporter.exportJSON(roots: roots, songs: songs)
        try data.write(to: destination)
        lastIndexExportPath = destination.path
        setStatusMessage("Exported index JSON (\(songs.count) songs).")
        diagnostics.log(.info, "Exported archive index to \(destination.path)")
    }

    func selectedSongExportContext() -> ArchiveDiagnosticsSelectedSongContext? {
        guard let song = selectedSong else { return nil }
        return ArchiveDiagnosticsSelectedSongContext.from(song: song)
    }

    func activeSearchExportContext() -> ArchiveDiagnosticsSearchContext? {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let matches = filteredSongs.map { song in
            ArchiveDiagnosticsSearchMatch(
                displayTitle: song.effectiveDisplayTitle,
                summary: searchMatchSummaries[song.id, default: ""]
            )
        }
        return ArchiveDiagnosticsSearchContext(query: trimmed, matches: matches)
    }

    func activeSkippedSearchExportContext() -> ArchiveDiagnosticsSkippedSearchContext? {
        ArchiveDiagnosticsSkippedSearchContext.from(
            query: searchQuery,
            results: skippedSearchMatches
        )
    }

    func exportDiagnostics() throws {
        guard let scanDiagnostics else {
            setStatusMessage("Scan the archive before exporting diagnostics.")
            return
        }
        let destination = try ArchiveExportPaths.stampedFileURL(
            subdirectory: "niko-music-hub-diagnostics",
            namePrefix: "scan",
            nameSuffix: "-\(UUID().uuidString.prefix(8)).txt"
        )
        try ArchiveDiagnosticsExporter.exportText(
            diagnostics: scanDiagnostics,
            to: destination,
            archiveRoots: roots,
            searchContext: activeSearchExportContext(),
            skippedSearchContext: activeSkippedSearchExportContext(),
            selectedSongContext: selectedSongExportContext()
        )
        lastDiagnosticsExportPath = destination.path
        diagnostics.log(.info, "Exported diagnostics to \(destination.path)")
    }

    func openLatestCPR(for song: Song) throws {
        if let result = try opener.openLatestCPR(
            for: song,
            dryRun: runtime.dryRunOpen,
            allowedRoots: roots
        ) {
            lastDryRunLog = result.path
            if runtime.dryRunOpen {
                let displayPath = Song.displayDryRunPath(result.path)
                print("[niko-music-hub-smoke] dry-run open: \(displayPath)")
            }
        }
    }

    func openMainPreview(for song: Song) throws {
        guard let id = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == id }) else { return }
        if runtime.dryRunOpen {
            let path = candidate.filePath.path
            lastDryRunLog = path
            print("[niko-music-hub-smoke] dry-run open preview: \(Song.displayDryRunPath(path))")
            return
        }
        fileActions.revealInFinder(candidate.filePath)
    }

    func preferredRevealURL(for song: Song) -> URL? {
        if let latest = song.effectiveLatestCPR?.filePath ?? song.visibleProjectVersions.first?.filePath {
            return latest
        }
        return song.folderPath
    }

    func revealInFinder(url: URL?) {
        guard let url else { return }
        fileActions.revealInFinder(url)
    }
}
