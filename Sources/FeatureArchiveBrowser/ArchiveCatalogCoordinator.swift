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
