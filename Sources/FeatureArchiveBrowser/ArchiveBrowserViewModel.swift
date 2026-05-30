import AppCore
import Foundation
import NikoMusicCore

/// Archive shell view model. Browse refresh and projection live in this file (``private(set)`` inputs).
/// Scan/cache: ``ArchiveBrowserViewModel+Scan``. Metadata: ``ArchiveBrowserViewModel+Metadata``. Exports: ``ArchiveBrowserViewModel+Exports``.
@MainActor
public final class ArchiveBrowserViewModel: ObservableObject {
    @Published public var roots: [URL] = []
    @Published var songs: [Song] = []
    @Published private(set) var filteredSongs: [Song] = []
    @Published private(set) var searchMatchSummaries: [String: String] = [:]
    @Published private(set) var skippedSearchMatches: [SkippedEntrySearchResult] = []
    @Published private(set) var searchQuery: String = ""
    @Published private(set) var selectedShelf: ArchiveSmartShelf = .allSongs
    @Published private(set) var selectedCollaboratorID: String?
    @Published var selectedSong: Song?
    @Published var isScanning = false
    @Published var statusMessage: String?
    @Published var scanDiagnostics: ArchiveScanDiagnostics?
    @Published var lastDryRunLog: String?
    @Published var lastDiagnosticsExportPath: String?
    @Published var lastIndexExportPath: String?
    @Published var needsFirstRunOnboarding = false
    @Published var collaborators: [Collaborator] = []
    @Published private(set) var showHiddenSongs = false
    @Published private(set) var sortMode: ArchiveBrowseSortMode = .titleAZ
    @Published private(set) var browseFilter: ArchiveBrowseFilter = []
    @Published var pendingCollaboratorSuggestions: [CollaboratorSuggestion] = []
    @Published var duplicateSongHints: [DuplicateSongHint] = []
    @Published var missingAudioReport: MissingAudioReport?
    @Published var mixdownBPMBySongID: [String: MixdownBPMEstimate] = [:]

    let scanner = CubaseArchiveScanner()
    private let browseRefreshDriver: ArchiveBrowseRefreshDriver
    let opener: MusicItemOpener
    let fileActions: any FileActions
    let settingsStore: SettingsStore
    let diagnostics: Diagnostics
    let archiveIndexStore: (any ArchiveIndexStoring)?
    let songMetadataStore: (any SongUserMetadataStoring)?
    let collaboratorStore: (any CollaboratorStoring)?
    let archiveRootWatcher: (any ArchiveRootWatching)?

    public init(
        context: ToolContext,
        archiveIndexStore: (any ArchiveIndexStoring)? = nil,
        songMetadataStore: (any SongUserMetadataStoring)? = nil,
        archiveRootWatcher: (any ArchiveRootWatching)? = nil,
        collaboratorStore: (any CollaboratorStoring)? = nil,
        browseSearchDebounceNanoseconds: UInt64 = 200_000_000
    ) {
        self.settingsStore = context.settingsStore
        self.diagnostics = context.diagnostics
        self.fileActions = context.fileActions
        self.archiveIndexStore = archiveIndexStore
        self.songMetadataStore = songMetadataStore
        self.collaboratorStore = collaboratorStore
        self.archiveRootWatcher = archiveRootWatcher
        self.browseRefreshDriver = ArchiveBrowseRefreshDriver(debounceNanoseconds: browseSearchDebounceNanoseconds)
        let dryRunOnly = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_DRY_RUN_OPEN"] == "1"
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
    }

    func loadRootsFromSettings() {
        if let env = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_FIXTURE_ROOT"], !env.isEmpty {
            roots = [URL(fileURLWithPath: env, isDirectory: true)]
            return
        }
        if let settings = try? settingsStore.loadSettings() {
            let loadedRoots = settings.archiveRoots.map(\.url)
            roots = ArchiveRootDisplayPolicy.publicRoots(from: loadedRoots)
            if roots.map(\.path) != loadedRoots.map(\.path) {
                persistRoots()
            }
        }
        applyBootstrapRootWhenEmpty()
        refreshFirstRunState()
    }

    func refreshFirstRunState() {
        if ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_FIXTURE_ROOT"] != nil {
            needsFirstRunOnboarding = false
            return
        }
        if !roots.isEmpty {
            needsFirstRunOnboarding = false
            return
        }
        let completed = (try? settingsStore.loadSettings())?.archiveOnboardingCompleted ?? false
        let hasDevBootstrap = ArchiveDefaultRootPolicy.bootstrapRoot() != nil
        needsFirstRunOnboarding = !completed && !hasDevBootstrap
    }

    func completeArchiveOnboarding() {
        try? settingsStore.updateSettings { settings in
            settings.archiveOnboardingCompleted = true
        }
        needsFirstRunOnboarding = false
    }

    private func applyBootstrapRootWhenEmpty() {
        if ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_SETTINGS_SUITE"] != nil {
            return
        }
        guard roots.isEmpty, let bootstrap = ArchiveDefaultRootPolicy.bootstrapRoot() else { return }
        roots = [bootstrap]
        persistRoots()
        completeArchiveOnboarding()
    }

    func persistRoots() {
        let snapshot = roots
        try? settingsStore.updateSettings { settings in
            settings.archiveRoots = snapshot.map { StoredArchiveRoot(path: $0.path) }
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
        }
    }

    public func removeRoot(_ url: URL) {
        roots.removeAll { $0.path == url.path }
        persistRoots()
        restartArchiveRootWatching()
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
        selectedSong = song
        refreshBPMEstimate(for: song)
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
        pendingCollaboratorSuggestions = ArchiveIntelligence.collaboratorSuggestions(
            songs: songs,
            collaborators: collaborators
        )
        duplicateSongHints = ArchiveIntelligence.duplicateSongHints(songs: songs)
        missingAudioReport = ArchiveIntelligence.missingAudioReport(songs: songs)
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
        collaborators = (try? collaboratorStore.loadAll()) ?? []
    }

    func upsertCollaborator(name: String) -> Collaborator? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let collaboratorStore else { return nil }
        let collaborator = Collaborator(displayName: trimmed)
        do {
            try collaboratorStore.upsert(collaborator)
            loadCollaborators()
            refreshIntelligence()
            return collaborator
        } catch {
            diagnostics.log(.error, "Collaborator save failed: \(error)")
            return nil
        }
    }

    func refreshBPMEstimate(for song: Song) {
        guard mixdownBPMBySongID[song.id] == nil,
              let id = song.mainPreviewCandidateID,
              let url = song.previewCandidates.first(where: { $0.id == id })?.filePath else { return }
        if let estimate = MixdownBPMEstimator.estimate(url: url) {
            mixdownBPMBySongID[song.id] = estimate
        }
    }

    func bpmEstimate(for song: Song) -> MixdownBPMEstimate? {
        mixdownBPMBySongID[song.id]
    }
}

// MARK: - Browse projection and refresh

extension ArchiveBrowserViewModel {
    func mutateBrowseInputs(_ updates: () -> Void) {
        browseRefreshDriver.cancelPendingDebounce()
        updates()
        recomputeBrowseResults()
    }

    func mutateCatalog(_ updates: () -> Void) {
        browseRefreshDriver.cancelPendingDebounce()
        updates()
        recomputeBrowseResults()
        refreshIntelligence()
    }

    func setSearchQuery(_ query: String, immediate: Bool = false) {
        searchQuery = query
        if immediate {
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
        let result = ArchiveBrowseProjection.project(browseState())
        filteredSongs = result.filteredSongs
        searchMatchSummaries = result.searchMatchSummaries
        skippedSearchMatches = result.skippedSearchMatches
    }
}
