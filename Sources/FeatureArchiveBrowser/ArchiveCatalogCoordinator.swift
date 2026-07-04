import AppCore
import Foundation
import NikoMusicCore

/// Scan, cache, and metadata merge/persist for the archive catalog. Owned by ``ArchiveBrowserViewModel``;
/// browse/UI orchestration stays in the view model.
@MainActor
struct ArchiveCatalogCoordinator {
    private let scanner = CubaseArchiveScanner()
    let archiveIndexStore: (any ArchiveIndexStoring)?
    let songMetadataStore: (any SongUserMetadataStoring)?
    let collaboratorStore: (any CollaboratorStoring)?
    let diagnostics: Diagnostics

    func performScanSynchronously(roots: [URL]) throws -> ScanResult {
        try scanner.scan(roots: roots)
    }

    func performScanDetached(roots: [URL]) async throws -> ScanResult {
        let scanner = scanner
        return try await Task.detached(priority: .userInitiated) {
            try scanner.scan(roots: roots)
        }.value
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
        let scanner = scanner
        let result = try await Task.detached(priority: .userInitiated) {
            try scanner.scanIncremental(resolution: resolution, roots: roots)
        }.value
        let affectedSongIDs = Self.affectedSongIDs(
            resolution: resolution,
            existing: existingSongs
        )
        return (result, affectedSongIDs)
    }

    static func mergeIncrementalScan(
        existing: [Song],
        incremental: ScanResult,
        affectedSongIDs: Set<String>
    ) -> [Song] {
        let incomingByID = Dictionary(uniqueKeysWithValues: incremental.songs.map { ($0.id, $0) })
        var merged: [Song] = []
        merged.reserveCapacity(existing.count + incremental.songs.count)

        for song in existing {
            guard affectedSongIDs.contains(song.id) else {
                merged.append(song)
                continue
            }
            if let updated = incomingByID[song.id] {
                merged.append(updated)
            }
        }

        let mergedIDs = Set(merged.map(\.id))
        for song in incremental.songs where !mergedIDs.contains(song.id) {
            merged.append(song)
        }

        merged.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        return merged
    }

    private static func affectedSongIDs(
        resolution: ArchiveSongFolderResolver.Resolution,
        existing: [Song]
    ) -> Set<String> {
        var ids = Set(resolution.songFolders.map { $0.standardizedFileURL.path })

        guard !resolution.rootsForRootLevelScan.isEmpty else { return ids }

        let rootPaths = Set(resolution.rootsForRootLevelScan.map { $0.standardizedFileURL.path })
        for song in existing {
            let songPath = song.folderPath.standardizedFileURL.path
            for rootPath in rootPaths where isImmediateChildPath(songPath, ofRoot: rootPath) {
                ids.insert(song.id)
            }
        }
        for song in existing where rootPaths.contains(song.folderPath.standardizedFileURL.path) {
            ids.insert(song.id)
        }
        return ids
    }

    private static func isImmediateChildPath(_ path: String, ofRoot rootPath: String) -> Bool {
        guard path.hasPrefix(rootPath + "/") else { return false }
        let relative = String(path.dropFirst(rootPath.count + 1))
        return !relative.contains("/")
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

    func loadCachedSongs(
        roots: [URL],
        collaborators: [Collaborator]
    ) -> ArchiveCacheLoadResult {
        guard let archiveIndexStore else { return .empty }
        let snapshot: ArchiveIndexSnapshot?
        do {
            snapshot = try archiveIndexStore.loadLatest()
        } catch {
            diagnostics.log(.error, "Archive cache load failed: \(error)")
            return .failed("Archive cache could not be loaded: \(error.localizedDescription)")
        }
        guard let snapshot else { return .empty }
        guard snapshot.matchesCurrentRoots(roots), !snapshot.songs.isEmpty else { return .empty }
        let songs = mergeUserMetadata(into: snapshot.songs, collaborators: collaborators)
        return .loaded(songs: songs, scannedAt: snapshot.scannedAt)
    }

    func persistCachedIndex(roots: [URL], songs: [Song], scannedAt: Date) -> String? {
        guard let archiveIndexStore else { return nil }
        let snapshot = ArchiveIndexSnapshot(
            roots: roots.map { $0.standardizedFileURL.path },
            songs: songs,
            scannedAt: scannedAt
        )
        do {
            try archiveIndexStore.save(snapshot)
        } catch {
            diagnostics.log(.error, "Archive cache save failed: \(error)")
            return "Archive cache could not be saved: \(error.localizedDescription)"
        }
        return nil
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
}

enum ArchiveCacheLoadResult {
    case loaded(songs: [Song], scannedAt: Date)
    case empty
    case failed(String)
}
