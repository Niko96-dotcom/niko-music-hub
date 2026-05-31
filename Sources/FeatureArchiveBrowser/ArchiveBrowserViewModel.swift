import AppCore
import Foundation
import NikoMusicCore

/// Archive shell view model. Browse, scan, metadata, and exports are split by MARK in this file
/// so catalog/browse invariants stay ``private`` without cross-file extension leaks.
@MainActor
public final class ArchiveBrowserViewModel: ObservableObject {
    @Published public var roots: [URL] = []
    @Published private(set) var songs: [Song] = []
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

    private let catalog: ArchiveCatalogCoordinator
    private let browseRefreshDriver: ArchiveBrowseRefreshDriver
    private var bpmEstimateTask: Task<Void, Never>?
    private let opener: MusicItemOpener
    private let fileActions: any FileActions
    private let settingsStore: SettingsStore
    private let diagnostics: Diagnostics
    private let collaboratorStore: (any CollaboratorStoring)?
    private let archiveRootWatcher: (any ArchiveRootWatching)?
    private let runtime: MusicHubRuntimeEnvironment

    public init(
        context: ToolContext,
        archiveIndexStore: (any ArchiveIndexStoring)? = nil,
        songMetadataStore: (any SongUserMetadataStoring)? = nil,
        archiveRootWatcher: (any ArchiveRootWatching)? = nil,
        collaboratorStore: (any CollaboratorStoring)? = nil,
        browseSearchDebounceNanoseconds: UInt64 = 200_000_000,
        runtime: MusicHubRuntimeEnvironment = .current
    ) {
        self.settingsStore = context.settingsStore
        self.diagnostics = context.diagnostics
        self.fileActions = context.fileActions
        self.collaboratorStore = collaboratorStore
        self.archiveRootWatcher = archiveRootWatcher
        self.runtime = runtime
        self.catalog = ArchiveCatalogCoordinator(
            archiveIndexStore: archiveIndexStore,
            songMetadataStore: songMetadataStore,
            collaboratorStore: collaboratorStore,
            diagnostics: context.diagnostics
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
        let loadedCache = loadCachedIndexIfAvailable()
        if archiveRootWatcher != nil, !loadedCache, !roots.isEmpty, !runtime.usesFixtureRoot {
            statusMessage = "Scanning archive..."
            Task { await scan() }
        }
    }

    func loadRootsFromSettings() {
        if let fixtureRoot = runtime.fixtureRootURL {
            roots = [fixtureRoot]
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
        try? settingsStore.updateSettings { settings in
            settings.archiveOnboardingCompleted = true
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
            statusMessage = "Scanning archive..."
            Task { await scan() }
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
            refreshIntelligence()
            return collaborator
        } catch {
            diagnostics.log(.error, "Collaborator save failed: \(error)")
            return nil
        }
    }

    func refreshBPMEstimate(for song: Song) {
        bpmEstimateTask?.cancel()
        guard mixdownBPMBySongID[song.id] == nil,
              let id = song.mainPreviewCandidateID,
              let url = song.previewCandidates.first(where: { $0.id == id })?.filePath else { return }
        let songID = song.id
        bpmEstimateTask = Task {
            let estimate = await Task.detached(priority: .utility) {
                MixdownBPMEstimator.estimate(url: url)
            }.value
            guard !Task.isCancelled,
                  let estimate,
                  selectedSong?.id == songID,
                  mixdownBPMBySongID[songID] == nil else { return }
            mixdownBPMBySongID[songID] = estimate
        }
    }

    func bpmEstimate(for song: Song) -> MixdownBPMEstimate? {
        mixdownBPMBySongID[song.id]
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

// MARK: - Scan and cache

extension ArchiveBrowserViewModel {
    func clearScanResults() {
        mutateCatalog {
            songs = []
            scanDiagnostics = nil
            selectedSong = nil
            statusMessage = nil
        }
    }

    func scan() async {
        guard let rootsSnapshot = beginScan() else { return }
        defer { isScanning = false }
        do {
            let scannedAt = Date()
            let result = try await catalog.performScanDetached(roots: rootsSnapshot)
            applyScanResult(result, roots: rootsSnapshot, scannedAt: scannedAt)
        } catch {
            recordScanFailure(error)
        }
    }

    func scanSync() {
        guard let rootsSnapshot = beginScan() else { return }
        defer { isScanning = false }
        do {
            let result = try catalog.performScanSynchronously(roots: rootsSnapshot)
            applyScanResult(result, roots: rootsSnapshot, scannedAt: Date())
        } catch {
            recordScanFailure(error)
        }
    }

    private func beginScan() -> [URL]? {
        guard !roots.isEmpty else {
            statusMessage = "Add at least one archive root."
            return nil
        }
        guard !isScanning else { return nil }
        isScanning = true
        statusMessage = "Scanning archive..."
        return roots
    }

    private func recordScanFailure(_ error: Error) {
        mutateCatalog {
            scanDiagnostics = nil
            statusMessage = "Scan failed: \(error.localizedDescription)"
        }
        diagnostics.log(.error, statusMessage ?? "scan failed")
    }

    private func applyScanResult(_ result: ScanResult, roots: [URL], scannedAt: Date) {
        let built = catalog.buildDiagnostics(result: result, roots: roots, scannedAt: scannedAt)
        mutateCatalog {
            songs = catalog.mergeUserMetadata(into: result.songs, collaborators: collaborators)
            scanDiagnostics = built
            statusMessage = built.compactSummaryLine
        }
        diagnostics.log(.info, built.summaryLine)
        catalog.persistCachedIndex(roots: roots, songs: songs, scannedAt: scannedAt)
        catalog.persistUserMetadata(for: songs)
    }

    @discardableResult
    private func loadCachedIndexIfAvailable() -> Bool {
        guard let cached = catalog.loadCachedSongs(roots: roots, collaborators: collaborators) else { return false }
        mutateCatalog {
            songs = cached.songs
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let relative = formatter.localizedString(for: cached.scannedAt, relativeTo: Date())
            statusMessage = "Loaded \(cached.songs.count) songs from cache (\(relative)). Scan to refresh."
        }
        return true
    }

    private func restartArchiveRootWatching() {
        guard let archiveRootWatcher else { return }
        let rootsSnapshot = roots
        archiveRootWatcher.setRoots(rootsSnapshot) { [weak self] in
            guard let self else { return }
            guard !self.isScanning, !self.roots.isEmpty else { return }
            Task { await self.scan() }
        }
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

    func setManualMainPreview(for song: Song, candidateID: String) {
        guard songs.first(where: { $0.id == song.id })?.previewCandidates.contains(where: { $0.id == candidateID }) == true else {
            return
        }
        applyMetadataMerge(for: song) { metadata, _ in
            metadata.previewSelectionMode = .manual
            metadata.manualMainPreviewID = candidateID
        }
    }

    func revertPreviewToAuto(for song: Song) {
        applyMetadataMerge(for: song, rankingRefresh: .previewAuto) { metadata, scanned in
            metadata.previewSelectionMode = .auto
            metadata.manualMainPreviewID = nil
            scanned.previewSelectionMode = .auto
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
            selectedSong = nil
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
        catalog.persistUserMetadata(for: [created])
        if !roots.isEmpty {
            catalog.persistCachedIndex(
                roots: roots,
                songs: songs,
                scannedAt: scanDiagnostics?.scannedAt ?? Date()
            )
        }
        selectSong(created)
        try openLatestCPR(for: created)
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
        catalog.persistUserMetadata(for: [updated])
        if !roots.isEmpty {
            catalog.persistCachedIndex(
                roots: roots,
                songs: songs,
                scannedAt: scanDiagnostics?.scannedAt ?? Date()
            )
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
            statusMessage = "Export failed: \(error.localizedDescription)"
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
        statusMessage = "Exported index JSON (\(songs.count) songs)."
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
            statusMessage = "Scan the archive before exporting diagnostics."
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
        if let result = try opener.openLatestCPR(for: song, dryRun: runtime.dryRunOpen) {
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
