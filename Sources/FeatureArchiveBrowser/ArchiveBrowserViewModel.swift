import AppCore
import Foundation
import NikoMusicCore

@MainActor
public final class ArchiveBrowserViewModel: ObservableObject {
    @Published var roots: [URL] = []
    @Published var songs: [Song] = []
    @Published var filteredSongs: [Song] = []
    @Published var searchMatchSummaries: [String: String] = [:]
    @Published var skippedSearchMatches: [SkippedEntrySearchResult] = []
    @Published var searchQuery: String = ""
    @Published var selectedSong: Song?
    @Published var isScanning = false
    @Published var statusMessage: String?
    @Published var scanDiagnostics: ArchiveScanDiagnostics?
    @Published var lastDryRunLog: String?
    @Published var lastDiagnosticsExportPath: String?

    private let scanner = CubaseArchiveScanner()
    private var searchIndex = MusicSearchIndex()
    private let opener: MusicItemOpener
    private let settingsStore: SettingsStore
    private let diagnostics: Diagnostics

    public init(context: ToolContext) {
        self.settingsStore = context.settingsStore
        self.diagnostics = context.diagnostics
        let dryRunOnly = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_DRY_RUN_OPEN"] == "1"
        self.opener = MusicItemOpener(
            workspace: dryRunOnly ? nil : AppKitWorkspaceOpener(),
            log: { [diagnostics] message in
                diagnostics.log(.info, message)
            }
        )
        loadRootsFromSettings()
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
    }

    private func applyBootstrapRootWhenEmpty() {
        guard roots.isEmpty, let bootstrap = ArchiveDefaultRootPolicy.bootstrapRoot() else { return }
        roots = [bootstrap]
        persistRoots()
    }

    func persistRoots() {
        let snapshot = roots
        try? settingsStore.updateSettings { settings in
            settings.archiveRoots = snapshot.map { StoredArchiveRoot(path: $0.path) }
        }
    }

    func addRoot(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !roots.contains(where: { $0.path == standardized.path }) else { return }
        roots.append(standardized)
        persistRoots()
    }

    func removeRoot(_ url: URL) {
        roots.removeAll { $0.path == url.path }
        persistRoots()
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
            songs = result.songs
            searchIndex.rebuild(from: songs)
            applySearchFilter()
            let built = ArchiveScanDiagnosticsBuilder.build(
                result: result,
                roots: rootsSnapshot,
                scannedAt: scannedAt
            )
            scanDiagnostics = built
            statusMessage = built.compactSummaryLine
            diagnostics.log(.info, built.summaryLine)
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
            songs = result.songs
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
        } catch {
            scanDiagnostics = nil
            statusMessage = "Scan failed: \(error.localizedDescription)"
            diagnostics.log(.error, statusMessage ?? "scan failed")
        }
    }

    func applySearchFilter() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            filteredSongs = songs
            searchMatchSummaries = [:]
            skippedSearchMatches = []
            return
        }

        let results = searchIndex.searchResults(searchQuery)
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
                displayTitle: song.displayTitle,
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
}
