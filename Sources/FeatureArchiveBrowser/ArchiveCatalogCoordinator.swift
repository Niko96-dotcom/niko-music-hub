import AppCore
import Foundation
import NikoMusicCore

/// Scan, cache, and metadata merge/persist for the archive catalog. Owned by ``ArchiveBrowserViewModel``;
/// browse/UI orchestration stays in the view model.
@MainActor
struct ArchiveCatalogCoordinator {
    let archiveIndexStore: (any ArchiveIndexStoring)?
    let songMetadataStore: (any SongUserMetadataStoring)?
    let collaboratorStore: (any CollaboratorStoring)?
    let diagnostics: Diagnostics
    private let settingsStore: SettingsStore?

    init(
        archiveIndexStore: (any ArchiveIndexStoring)?,
        songMetadataStore: (any SongUserMetadataStoring)?,
        collaboratorStore: (any CollaboratorStoring)?,
        diagnostics: Diagnostics,
        settingsStore: SettingsStore? = nil
    ) {
        self.archiveIndexStore = archiveIndexStore
        self.songMetadataStore = songMetadataStore
        self.collaboratorStore = collaboratorStore
        self.diagnostics = diagnostics
        self.settingsStore = settingsStore
    }

    private static func loadExclusionTerms(settingsStore: SettingsStore?) -> [String] {
        guard let settingsStore,
              let settings = try? settingsStore.loadSettings() else { return [] }
        return ScanExclusionPolicy.terms(from: settings.scanExclusionTerms)
    }

    func performScanSynchronously(roots: [URL]) throws -> ScanResult {
        let scanner = CubaseArchiveScanner(
            exclusionTerms: Self.loadExclusionTerms(settingsStore: settingsStore)
        )
        return try scanner.scan(roots: roots)
    }

    func performScanDetached(roots: [URL]) async throws -> ScanResult {
        let exclusionTerms = Self.loadExclusionTerms(settingsStore: settingsStore)
        return try await Task.detached(priority: .userInitiated) {
            try CubaseArchiveScanner(exclusionTerms: exclusionTerms).scan(roots: roots)
        }.value
    }

    struct IncrementalFilesystemApplyResult: Sendable {
        let songs: [Song]
        let diagnostics: ArchiveScanDiagnostics
        let incrementalSongCount: Int
        let firstUpdatedTitle: String?
        let scannedAt: Date

        var statusMessage: String {
            if incrementalSongCount == 1, let firstUpdatedTitle {
                return "Updated \(firstUpdatedTitle) from filesystem change (\(songs.count) songs)."
            }
            return "Updated \(incrementalSongCount) songs from filesystem change (\(songs.count) total)."
        }

        var catalogApplyResult: CatalogScanApplyResult {
            CatalogScanApplyResult(
                songs: songs,
                diagnostics: diagnostics,
                statusMessage: statusMessage,
                scannedAt: scannedAt,
                shouldPersistUserMetadata: false
            )
        }
    }

    struct CatalogScanApplyResult: Sendable {
        let songs: [Song]
        let diagnostics: ArchiveScanDiagnostics
        let statusMessage: String
        let scannedAt: Date
        let shouldPersistUserMetadata: Bool
    }

    func applyFullScanResult(
        result: ScanResult,
        roots: [URL],
        collaborators: [Collaborator],
        scannedAt: Date
    ) -> CatalogScanApplyResult {
        let uniqueSongs = SongCatalogDeduplicator.uniqueByID(result.songs)
        let withMetadata = mergeUserMetadata(into: uniqueSongs, collaborators: collaborators)
        let mergedResult = ScanResult(
            songs: withMetadata,
            globalWarnings: result.globalWarnings,
            skippedEntries: result.skippedEntries
        )
        let built = buildDiagnostics(result: mergedResult, roots: roots, scannedAt: scannedAt)
        return CatalogScanApplyResult(
            songs: withMetadata,
            diagnostics: built,
            statusMessage: built.compactSummaryLine,
            scannedAt: scannedAt,
            shouldPersistUserMetadata: true
        )
    }

    func applyIncrementalFilesystemUpdate(
        changedPaths: [URL],
        roots: [URL],
        existingSongs: [Song],
        collaborators: [Collaborator],
        priorDiagnostics: ArchiveScanDiagnostics?
    ) async throws -> IncrementalFilesystemApplyResult? {
        let scannedAt = Date()
        let incremental = try await performIncrementalScanDetached(
            changedPaths: changedPaths,
            roots: roots,
            existingSongs: existingSongs
        )
        guard !incremental.affectedSongIDs.isEmpty || !incremental.result.songs.isEmpty else {
            return nil
        }

        // The merge stats every existing song folder — keep it off the main actor
        // (archives on slow/external volumes make each stat call visible).
        let merged = await Task.detached(priority: .userInitiated) { [result = incremental.result, affectedSongIDs = incremental.affectedSongIDs] in
            Self.mergeIncrementalScan(
                existing: existingSongs,
                incremental: result,
                affectedSongIDs: affectedSongIDs
            )
        }.value
        let uniqueMerged = SongCatalogDeduplicator.uniqueByID(merged)
        let withMetadata = mergeUserMetadata(into: uniqueMerged, collaborators: collaborators)
        let mergedResult = ScanResult(
            songs: withMetadata,
            globalWarnings: incremental.result.globalWarnings,
            skippedEntries: incremental.result.skippedEntries
        )
        let built = buildDiagnostics(result: mergedResult, roots: roots, scannedAt: scannedAt)
        return IncrementalFilesystemApplyResult(
            songs: withMetadata,
            diagnostics: ArchiveScanDiagnosticsBuilder.mergeIncremental(prior: priorDiagnostics, built: built),
            incrementalSongCount: incremental.result.songs.count,
            firstUpdatedTitle: incremental.result.songs.first?.displayTitle,
            scannedAt: scannedAt
        )
    }

    func performIncrementalScanDetached(
        changedPaths: [URL],
        roots: [URL],
        existingSongs: [Song]
    ) async throws -> (result: ScanResult, affectedSongIDs: Set<String>) {
        let resolution = ArchiveSongFolderResolver.resolve(changedPaths: changedPaths, roots: roots)
        guard !resolution.isEmpty else {
            return (ScanResult(), [])
        }
        let exclusionTerms = Self.loadExclusionTerms(settingsStore: settingsStore)
        let result = try await Task.detached(priority: .userInitiated) {
            try CubaseArchiveScanner(exclusionTerms: exclusionTerms)
                .scanIncremental(resolution: resolution, roots: roots)
        }.value
        let affectedSongIDs = Self.affectedSongIDs(
            resolution: resolution,
            existing: existingSongs
        )
        return (result, affectedSongIDs)
    }

    nonisolated static func mergeIncrementalScan(
        existing: [Song],
        incremental: ScanResult,
        affectedSongIDs: Set<String>,
        fileManager: FileManager = .default
    ) -> [Song] {
        let uniqueExisting = SongCatalogDeduplicator.uniqueByID(existing)
        let uniqueIncoming = SongCatalogDeduplicator.uniqueByID(incremental.songs)
        let incomingByID = uniqueIncoming.reduce(into: [String: Song]()) { $0[$1.id] = $1 }
        var merged: [Song] = []
        merged.reserveCapacity(uniqueExisting.count + uniqueIncoming.count)

        for song in uniqueExisting {
            let folderStillExists = fileManager.fileExists(atPath: song.folderPath.path)
            // Drop ghosts even when FSEvents did not mark the old path as affected
            // (common for Finder renames that only emit create events on the new name).
            if !affectedSongIDs.contains(song.id) {
                if folderStillExists {
                    merged.append(song)
                }
                continue
            }
            if let updated = incomingByID[song.id] {
                merged.append(updated)
            } else if folderStillExists {
                merged.append(song)
            }
        }

        let mergedIDs = Set(merged.map(\.id))
        for song in uniqueIncoming where !mergedIDs.contains(song.id) {
            merged.append(song)
        }

        merged.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        return merged
    }

    private static func affectedSongIDs(
        resolution: ArchiveSongFolderResolver.Resolution,
        existing: [Song]
    ) -> Set<String> {
        // Song.id is the standardized song-folder path; resolver returns folder URLs.
        var ids = Set(resolution.songFolders.map { $0.standardizedFileURL.path })

        guard !resolution.rootsForRootLevelScan.isEmpty else { return ids }

        let rootPaths = Set(resolution.rootsForRootLevelScan.map { $0.standardizedFileURL.path })
        for song in existing {
            let songPath = song.folderPath.standardizedFileURL.path
            for rootPath in rootPaths where isRootLevelCPRPath(songPath, ofRoot: rootPath) {
                ids.insert(song.id)
            }
        }
        return ids
    }

    private static func isRootLevelCPRPath(_ path: String, ofRoot rootPath: String) -> Bool {
        guard path.hasPrefix(rootPath + "/") else { return false }
        let relative = String(path.dropFirst(rootPath.count + 1))
        return !relative.contains("/") && relative.lowercased().hasSuffix(".cpr")
    }

    func buildDiagnostics(
        result: ScanResult,
        roots: [URL],
        scannedAt: Date
    ) -> ArchiveScanDiagnostics {
        ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: roots,
            scannedAt: scannedAt
        )
    }

    func mergeUserMetadata(
        into scanned: [Song],
        collaborators: [Collaborator]
    ) -> [Song] {
        guard songMetadataStore != nil || collaboratorStore != nil else { return scanned }
        let metadata: [String: SongUserMetadata]
        do {
            metadata = try songMetadataStore?.loadAll() ?? [:]
        } catch {
            diagnostics.log(.error, "Song metadata load failed: \(error)")
            metadata = [:]
        }
        let map = Dictionary(uniqueKeysWithValues: collaborators.map { ($0.id, $0) })
        return ArchiveMetadataMerger.merge(
            scanned: scanned,
            metadataByID: metadata,
            collaboratorsByID: map
        )
    }

    /// Launch-time cache bootstrap. Decoding a real catalog snapshot is tens of MB of JSON,
    /// so the load, metadata merge, and decode all run off the main actor.
    func loadCachedSongsDetached(
        roots: [URL],
        collaborators: [Collaborator]
    ) async -> ArchiveCacheLoadResult {
        guard let archiveIndexStore else { return .empty }
        let songMetadataStore = self.songMetadataStore
        let hasMetadataSources = songMetadataStore != nil || collaboratorStore != nil
        let outcome = await Task.detached(priority: .userInitiated) {
            () -> (result: ArchiveCacheLoadResult, logs: [String]) in
            let snapshot: ArchiveIndexSnapshot?
            do {
                snapshot = try archiveIndexStore.loadLatest()
            } catch {
                return (
                    .failed("Archive cache could not be loaded: \(error.localizedDescription)"),
                    ["Archive cache load failed: \(error)"]
                )
            }
            guard let snapshot, snapshot.matchesCurrentRoots(roots), !snapshot.songs.isEmpty else {
                return (.empty, [])
            }
            guard hasMetadataSources else {
                return (.loaded(songs: SongCatalogDeduplicator.uniqueByID(snapshot.songs), scannedAt: snapshot.scannedAt), [])
            }
            var logs: [String] = []
            let metadata: [String: SongUserMetadata]
            do {
                metadata = try songMetadataStore?.loadAll() ?? [:]
            } catch {
                logs.append("Song metadata load failed: \(error)")
                metadata = [:]
            }
            let map = Dictionary(uniqueKeysWithValues: collaborators.map { ($0.id, $0) })
            let merged = ArchiveMetadataMerger.merge(
                scanned: SongCatalogDeduplicator.uniqueByID(snapshot.songs),
                metadataByID: metadata,
                collaboratorsByID: map
            )
            return (.loaded(songs: merged, scannedAt: snapshot.scannedAt), logs)
        }.value
        for log in outcome.logs {
            diagnostics.log(.error, log)
        }
        return outcome.result
    }

    func persistUserMetadata(for songs: [Song]) -> String? {
        guard let songMetadataStore, !songs.isEmpty else { return nil }
        let items = songs.map { SongUserMetadata.from(song: $0) }
        do {
            try songMetadataStore.upsertAll(items)
        } catch {
            diagnostics.log(.error, "Song metadata save failed: \(error)")
            return "Song metadata could not be saved: \(error.localizedDescription)"
        }
        return nil
    }

    /// Off-main-actor variant of ``persistCachedIndex(roots:songs:scannedAt:)`` — encoding the
    /// whole catalog to JSON is proportional to catalog size and stalls the UI on the main actor.
    func persistCachedIndexDetached(roots: [URL], songs: [Song], scannedAt: Date) async -> String? {
        guard let archiveIndexStore else { return nil }
        let snapshot = ArchiveIndexSnapshot(
            roots: roots.map { $0.standardizedFileURL.path },
            songs: SongCatalogDeduplicator.uniqueByID(songs),
            scannedAt: scannedAt
        )
        let failure = await Task.detached(priority: .utility) { () -> (log: String, warning: String)? in
            do {
                try archiveIndexStore.save(snapshot)
                return nil
            } catch {
                return ("\(error)", error.localizedDescription)
            }
        }.value
        guard let failure else { return nil }
        diagnostics.log(.error, "Archive cache save failed: \(failure.log)")
        return "Archive cache could not be saved: \(failure.warning)"
    }
}

enum ArchiveCacheLoadResult {
    case loaded(songs: [Song], scannedAt: Date)
    case empty
    case failed(String)
}
