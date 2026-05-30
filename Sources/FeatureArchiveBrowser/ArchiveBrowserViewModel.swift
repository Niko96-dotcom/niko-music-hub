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
    @Published var selectedSong: Song?
    @Published var isScanning = false
    @Published var statusMessage: String?
    @Published var scanDiagnostics: ArchiveScanDiagnostics?
    @Published var lastDryRunLog: String?
    @Published var lastDiagnosticsExportPath: String?
    @Published var needsFirstRunOnboarding = false

    private let scanner = CubaseArchiveScanner()
    private var searchIndex = MusicSearchIndex()
    private let opener: MusicItemOpener
    private let fileActions: any FileActions
    private let settingsStore: SettingsStore
    private let diagnostics: Diagnostics
    private let archiveIndexStore: (any ArchiveIndexStoring)?
    private let songMetadataStore: (any SongUserMetadataStoring)?
    private let archiveRootWatcher: (any ArchiveRootWatching)?

    public init(
        context: ToolContext,
        archiveIndexStore: (any ArchiveIndexStoring)? = nil,
        songMetadataStore: (any SongUserMetadataStoring)? = nil,
        archiveRootWatcher: (any ArchiveRootWatching)? = nil
    ) {
        self.settingsStore = context.settingsStore
        self.diagnostics = context.diagnostics
        self.fileActions = context.fileActions
        self.archiveIndexStore = archiveIndexStore
        self.songMetadataStore = songMetadataStore
        self.archiveRootWatcher = archiveRootWatcher
        let dryRunOnly = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_DRY_RUN_OPEN"] == "1"
        self.opener = MusicItemOpener(
            workspace: dryRunOnly ? nil : AppKitWorkspaceOpener(),
            log: { [diagnostics] message in
                diagnostics.log(.info, message)
            }
        )
        loadRootsFromSettings()
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

    /// Synchronous scan for tests and smoke tooling (blocks the caller).
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

    func applySearchFilter() {
        let shelfSongs = songsForSelectedShelf()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            filteredSongs = shelfSongs
            searchMatchSummaries = [:]
            skippedSearchMatches = []
            return
        }

        let scopedIndex = MusicSearchIndex(songs: shelfSongs)
        let results = scopedIndex.searchResults(searchQuery)
        filteredSongs = results.map(\.song)
        searchMatchSummaries = Dictionary(
            uniqueKeysWithValues: results.map { ($0.song.id, $0.matchSummary) }
        )
        let skipped = scanDiagnostics?.skippedEntries ?? []
        skippedSearchMatches = SkippedEntrySearchMatcher.search(searchQuery, in: skipped)
    }

    func selectSong(_ song: Song) {
        selectedSong = song
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

    func preferredRevealURL(for song: Song) -> URL? {
        if let latest = song.latestCPR?.filePath ?? song.projectVersions.first?.filePath {
            return latest
        }
        return song.folderPath
    }

    func revealInFinder(url: URL?) {
        guard let url else { return }
        fileActions.revealInFinder(url)
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
        let merged = ArchiveMetadataMerger.merge(scanned: scanned, metadata: metadata)
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
        let merged = ArchiveMetadataMerger.merge(scanned: scanned, metadata: metadata)
        commitSongMetadataUpdate(merged)
    }

    private func commitSongMetadataUpdate(_ updated: Song) {
        replaceSong(updated)
        persistUserMetadata(for: [updated])
        if !roots.isEmpty {
            persistCachedIndex(roots: roots, scannedAt: scanDiagnostics?.scannedAt ?? Date())
        }
    }

    func songsForSelectedShelf() -> [Song] {
        ArchiveShelfRanker.filter(songs, shelf: selectedShelf)
    }

    func selectShelf(_ shelf: ArchiveSmartShelf) {
        selectedShelf = shelf
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
        guard let songMetadataStore else { return scanned }
        let metadata = (try? songMetadataStore.loadAll()) ?? [:]
        return ArchiveMetadataMerger.merge(scanned: scanned, metadataByID: metadata)
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
