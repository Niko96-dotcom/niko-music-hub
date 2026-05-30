import AppCore
import Foundation
import NikoMusicCore

@MainActor
public final class ArchiveBrowserViewModel: ObservableObject {
    @Published public var roots: [URL] = []
    @Published var songs: [Song] = []
    @Published var filteredSongs: [Song] = []
    @Published var searchMatchSummaries: [String: String] = [:]
    @Published var skippedSearchMatches: [SkippedEntrySearchResult] = []
    @Published var searchQuery: String = ""
    @Published var selectedShelf: ArchiveSmartShelf = .allSongs
    @Published var selectedCollaboratorID: String?
    @Published var selectedSong: Song?
    @Published var isScanning = false
    @Published var statusMessage: String?
    @Published var scanDiagnostics: ArchiveScanDiagnostics?
    @Published var lastDryRunLog: String?
    @Published var lastDiagnosticsExportPath: String?
    @Published var lastIndexExportPath: String?
    @Published var needsFirstRunOnboarding = false
    @Published var collaborators: [Collaborator] = []
    @Published var showHiddenSongs = false
    @Published var sortMode: ArchiveBrowseSortMode = .titleAZ
    @Published var browseFilter: ArchiveBrowseFilter = []
    @Published var pendingCollaboratorSuggestions: [CollaboratorSuggestion] = []
    @Published var duplicateSongHints: [DuplicateSongHint] = []
    @Published var missingAudioReport: MissingAudioReport?
    @Published var mixdownBPMBySongID: [String: MixdownBPMEstimate] = [:]

    private let scanner = CubaseArchiveScanner()
    private var searchIndex = MusicSearchIndex()
    private let opener: MusicItemOpener
    private let fileActions: any FileActions
    private let settingsStore: SettingsStore
    private let diagnostics: Diagnostics
    private let archiveIndexStore: (any ArchiveIndexStoring)?
    private let songMetadataStore: (any SongUserMetadataStoring)?
    private let collaboratorStore: (any CollaboratorStoring)?
    private let archiveRootWatcher: (any ArchiveRootWatching)?

    public init(
        context: ToolContext,
        archiveIndexStore: (any ArchiveIndexStoring)? = nil,
        songMetadataStore: (any SongUserMetadataStoring)? = nil,
        archiveRootWatcher: (any ArchiveRootWatching)? = nil,
        collaboratorStore: (any CollaboratorStoring)? = nil
    ) {
        self.settingsStore = context.settingsStore
        self.diagnostics = context.diagnostics
        self.fileActions = context.fileActions
        self.archiveIndexStore = archiveIndexStore
        self.songMetadataStore = songMetadataStore
        self.collaboratorStore = collaboratorStore
        self.archiveRootWatcher = archiveRootWatcher
        let dryRunOnly = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_DRY_RUN_OPEN"] == "1"
        self.opener = MusicItemOpener(
            workspace: dryRunOnly ? nil : AppKitWorkspaceOpener(),
            log: { [diagnostics] message in
                diagnostics.log(.info, message)
            }
        )
        loadRootsFromSettings()
        loadCollaborators()
        loadCachedIndexIfAvailable()
        refreshFirstRunState()
        restartArchiveRootWatching()
        applySearchFilter()
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

    func clearScanResults() {
        songs = []
        filteredSongs = []
        searchMatchSummaries = [:]
        skippedSearchMatches = []
        selectedSong = nil
        scanDiagnostics = nil
        statusMessage = nil
        searchIndex.rebuild(from: [])
        refreshIntelligence()
    }

    func scan() async {
        guard !roots.isEmpty else {
            statusMessage = "Add at least one archive root."
            return
        }
        guard !isScanning else { return }
        isScanning = true
        let rootsSnapshot = roots
        defer { isScanning = false }
        do {
            let scannedAt = Date()
            let scanner = scanner
            let result = try await Task.detached(priority: .userInitiated) {
                try scanner.scan(roots: rootsSnapshot)
            }.value
            applyScanResult(result, roots: rootsSnapshot, scannedAt: scannedAt)
        } catch {
            scanDiagnostics = nil
            statusMessage = "Scan failed: \(error.localizedDescription)"
            diagnostics.log(.error, statusMessage ?? "scan failed")
        }
    }

    func scanSync() {
        guard !roots.isEmpty else {
            statusMessage = "Add at least one archive root."
            return
        }
        isScanning = true
        defer { isScanning = false }
        do {
            let scannedAt = Date()
            let result = try scanner.scan(roots: roots)
            applyScanResult(result, roots: roots, scannedAt: scannedAt)
        } catch {
            scanDiagnostics = nil
            statusMessage = "Scan failed: \(error.localizedDescription)"
            diagnostics.log(.error, statusMessage ?? "scan failed")
        }
    }

    private func applyScanResult(_ result: ScanResult, roots: [URL], scannedAt: Date) {
        songs = mergeUserMetadata(into: result.songs)
        searchIndex.rebuild(from: songs)
        applySearchFilter()
        refreshIntelligence()
        let built = ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: roots,
            scannedAt: scannedAt
        )
        scanDiagnostics = built
        statusMessage = built.compactSummaryLine
        diagnostics.log(.info, built.summaryLine)
        persistCachedIndex(roots: roots, scannedAt: scannedAt)
        persistUserMetadata(for: songs)
    }

    private func loadCachedIndexIfAvailable() {
        guard let archiveIndexStore else { return }
        guard let snapshot = try? archiveIndexStore.loadLatest() else { return }
        guard snapshot.matchesCurrentRoots(roots), !snapshot.songs.isEmpty else { return }
        songs = mergeUserMetadata(into: snapshot.songs)
        searchIndex.rebuild(from: songs)
        applySearchFilter()
        refreshIntelligence()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: snapshot.scannedAt, relativeTo: Date())
        statusMessage = "Loaded \(snapshot.songs.count) songs from cache (\(relative)). Scan to refresh."
    }

    private func persistCachedIndex(roots: [URL], scannedAt: Date) {
        guard let archiveIndexStore else { return }
        let snapshot = ArchiveIndexSnapshot(
            roots: roots.map { $0.standardizedFileURL.path },
            songs: songs,
            scannedAt: scannedAt
        )
        do {
            try archiveIndexStore.save(snapshot)
        } catch {
            diagnostics.log(.error, "Archive cache save failed: \(error)")
        }
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

    func toggleBrowseFilter(_ filter: ArchiveBrowseFilter) {
        var next = browseFilter
        if next.contains(filter) {
            next.remove(filter)
        } else {
            next.insert(filter)
        }
        browseFilter = next
        applySearchFilter()
    }

    /// Runs an export action and surfaces failures on `statusMessage`.
    func performExport(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func applySearchFilter() {
        let shelfSongs = songsForSelectedShelf()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched: [Song]
        if trimmed.isEmpty {
            searched = shelfSongs
            searchMatchSummaries = [:]
            skippedSearchMatches = []
        } else {
            let scopedIndex = MusicSearchIndex(songs: shelfSongs)
            let results = scopedIndex.searchResults(searchQuery)
            searched = results.map(\.song)
            searchMatchSummaries = Dictionary(
                uniqueKeysWithValues: results.map { ($0.song.id, $0.matchSummary) }
            )
            let skipped = scanDiagnostics?.skippedEntries ?? []
            skippedSearchMatches = SkippedEntrySearchMatcher.search(searchQuery, in: skipped)
        }
        filteredSongs = ArchiveBrowseSortMode.sort(
            ArchiveBrowseFilter.apply(searched, filter: browseFilter),
            mode: sortMode
        )
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
            || !songs.isEmpty
            || scanDiagnostics != nil
            || !pendingCollaboratorSuggestions.isEmpty
    }

    var sidebarMorePanelSummary: String {
        let report = healthReport()
        var parts: [String] = []
        if report.totalSongs > 0 {
            parts.append("\(report.totalSongs) songs")
        }
        if report.withWarnings > 0 {
            parts.append("\(report.withWarnings) warnings")
        }
        if let skipped = scanDiagnostics?.skippedEntries.count, skipped > 0 {
            parts.append("\(skipped) skipped")
        }
        return parts.isEmpty ? "Health & intelligence" : parts.joined(separator: " · ")
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

    func exportIndexJSON() throws {
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("niko-music-hub-exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = exportDir.appendingPathComponent("archive-index-\(stamp).json")
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
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("niko-music-hub-diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = exportDir.appendingPathComponent("scan-\(stamp)-\(UUID().uuidString.prefix(8)).txt")
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
        let dryRun = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_DRY_RUN_OPEN"] == "1"
        if let result = try opener.openLatestCPR(for: song, dryRun: dryRun) {
            lastDryRunLog = result.path
            if dryRun {
                let displayPath = Song.displayDryRunPath(result.path)
                print("[niko-music-hub-smoke] dry-run open: \(displayPath)")
            }
        }
    }

    func openMainPreview(for song: Song) throws {
        guard let id = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == id }) else { return }
        let dryRun = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_DRY_RUN_OPEN"] == "1"
        if dryRun {
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

    func focusSelectedSongDetail() {
        // Selection drives detail pane; no-op hook for shortcuts.
    }

    func updateVirtualTitle(for song: Song, title: String) {
        guard var updated = latestSong(matching: song) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.virtualTitle = trimmed.isEmpty ? nil : trimmed
        commitSongMetadataUpdate(updated)
    }

    func updateAppNote(for song: Song, note: String) {
        guard var updated = latestSong(matching: song) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.appNote = trimmed.isEmpty ? nil : trimmed
        commitSongMetadataUpdate(updated)
    }

    func updateAliases(for song: Song, aliasesText: String) {
        guard var updated = latestSong(matching: song) else { return }
        let aliases = aliasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        updated.aliases = aliases
        commitSongMetadataUpdate(updated)
    }

    func setManualMainPreview(for song: Song, candidateID: String) {
        guard var updated = latestSong(matching: song) else { return }
        guard updated.previewCandidates.contains(where: { $0.id == candidateID }) else { return }
        updated.previewSelectionMode = .manual
        updated.mainPreviewCandidateID = candidateID
        commitSongMetadataUpdate(updated)
    }

    func revertPreviewToAuto(for song: Song) {
        guard let song = latestSong(matching: song) else { return }
        var metadata = SongUserMetadata.from(song: song)
        metadata.previewSelectionMode = .auto
        metadata.manualMainPreviewID = nil
        var scanned = song
        scanned.previewSelectionMode = .auto
        let context = PreviewRankingProjectContext.from(projectVersions: scanned.projectVersions)
        let ranker = PreviewConfidenceRanker()
        let ranked = ranker.rank(scanned.previewCandidates, projectContext: context)
        scanned.previewCandidates = ranked
        scanned.mainPreviewCandidateID = ranker.mainPreviewID(from: ranked)
        let merged = ArchiveMetadataMerger.merge(
            scanned: scanned,
            metadata: metadata,
            collaboratorsByID: collaboratorsByID()
        )
        commitSongMetadataUpdate(merged)
    }

    func ignorePreviewCandidate(for song: Song, candidateID: String) {
        guard let song = latestSong(matching: song) else { return }
        var metadata = SongUserMetadata.from(song: song)
        if !metadata.ignoredPreviewCandidateIDs.contains(candidateID) {
            metadata.ignoredPreviewCandidateIDs.append(candidateID)
        }
        if metadata.manualMainPreviewID == candidateID {
            metadata.previewSelectionMode = .auto
            metadata.manualMainPreviewID = nil
        }
        var scanned = song
        if scanned.mainPreviewCandidateID == candidateID {
            scanned.previewSelectionMode = .auto
        }
        let merged = ArchiveMetadataMerger.merge(
            scanned: scanned,
            metadata: metadata,
            collaboratorsByID: collaboratorsByID()
        )
        commitSongMetadataUpdate(merged)
    }

    func setManualMainCPR(for song: Song, versionID: String) {
        guard var updated = latestSong(matching: song) else { return }
        guard updated.visibleProjectVersions.contains(where: { $0.id == versionID }) else { return }
        updated.cprSelectionMode = .manual
        updated.manualMainCPRID = versionID
        updated.latestCPR = updated.visibleProjectVersions.first(where: { $0.id == versionID })
        commitSongMetadataUpdate(updated)
    }

    func revertCPRToAuto(for song: Song) {
        guard var updated = latestSong(matching: song) else { return }
        updated.cprSelectionMode = .auto
        updated.manualMainCPRID = nil
        let detector = CPRVersionDetector()
        updated.latestCPR = detector.latestCPR(from: updated.projectVersions)
        commitSongMetadataUpdate(updated)
    }

    func ignoreCPRVersion(for song: Song, versionID: String) {
        guard let song = latestSong(matching: song) else { return }
        var metadata = SongUserMetadata.from(song: song)
        if !metadata.ignoredCPRVersionIDs.contains(versionID) {
            metadata.ignoredCPRVersionIDs.append(versionID)
        }
        if metadata.manualMainCPRID == versionID {
            metadata.cprSelectionMode = .auto
            metadata.manualMainCPRID = nil
        }
        let merged = ArchiveMetadataMerger.merge(
            scanned: song,
            metadata: metadata,
            collaboratorsByID: collaboratorsByID()
        )
        commitSongMetadataUpdate(merged)
    }

    func setSongHidden(_ song: Song, hidden: Bool) {
        guard var updated = latestSong(matching: song) else { return }
        updated.isIgnored = hidden
        commitSongMetadataUpdate(updated)
        if hidden, selectedSong?.id == song.id {
            selectedSong = nil
        }
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

    func assignCollaborators(to song: Song, collaboratorIDs: [String]) {
        guard var updated = latestSong(matching: song) else { return }
        updated.collaboratorIDs = collaboratorIDs
        updated.collaboratorNames = collaboratorIDs.compactMap { id in
            collaborators.first(where: { $0.id == id })?.displayName
        }
        commitSongMetadataUpdate(updated)
        refreshIntelligence()
    }

    func createNewSong(request: NewSongRequest) throws -> Song {
        var created = try NewSongFolderCreator.create(request: request)
        created = mergeUserMetadata(into: [created]).first ?? created
        if !songs.contains(where: { $0.id == created.id }) {
            songs.append(created)
            songs.sort {
                $0.effectiveDisplayTitle.localizedCaseInsensitiveCompare($1.effectiveDisplayTitle) == .orderedAscending
            }
        }
        searchIndex.rebuild(from: songs)
        applySearchFilter()
        persistUserMetadata(for: [created])
        if !roots.isEmpty {
            persistCachedIndex(roots: roots, scannedAt: scanDiagnostics?.scannedAt ?? Date())
        }
        selectSong(created)
        refreshIntelligence()
        try openLatestCPR(for: created)
        return created
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

    private func commitSongMetadataUpdate(_ updated: Song) {
        replaceSong(updated)
        persistUserMetadata(for: [updated])
        if !roots.isEmpty {
            persistCachedIndex(roots: roots, scannedAt: scanDiagnostics?.scannedAt ?? Date())
        }
    }

    func songsForSelectedShelf() -> [Song] {
        let base = showHiddenSongs ? songs : songs.filter { !$0.isIgnored }
        return ArchiveShelfRanker.filter(
            base,
            shelf: selectedShelf,
            collaboratorID: selectedShelf == .byCollaborator ? selectedCollaboratorID : nil
        )
    }

    func selectShelf(_ shelf: ArchiveSmartShelf) {
        selectedShelf = shelf
        if shelf == .byCollaborator, selectedCollaboratorID == nil {
            selectedCollaboratorID = collaborators.first?.id
        }
        applySearchFilter()
    }

    private func latestSong(matching song: Song) -> Song? {
        songs.first { $0.id == song.id }
    }

    private func replaceSong(_ updated: Song) {
        if let index = songs.firstIndex(where: { $0.id == updated.id }) {
            songs[index] = updated
        }
        if selectedSong?.id == updated.id {
            selectedSong = updated
        }
        searchIndex.rebuild(from: songs)
        applySearchFilter()
    }

    private func mergeUserMetadata(into scanned: [Song]) -> [Song] {
        guard songMetadataStore != nil || collaboratorStore != nil else { return scanned }
        let metadata = (try? songMetadataStore?.loadAll()) ?? [:]
        let map = collaboratorsByID()
        return ArchiveMetadataMerger.merge(
            scanned: scanned,
            metadataByID: metadata,
            collaboratorsByID: map
        )
    }

    private func collaboratorsByID() -> [String: Collaborator] {
        Dictionary(uniqueKeysWithValues: collaborators.map { ($0.id, $0) })
    }

    private func persistUserMetadata(for songs: [Song]) {
        guard let songMetadataStore, !songs.isEmpty else { return }
        let items = songs.map { SongUserMetadata.from(song: $0) }
        do {
            try songMetadataStore.upsertAll(items)
        } catch {
            diagnostics.log(.error, "Song metadata save failed: \(error)")
        }
    }
}
