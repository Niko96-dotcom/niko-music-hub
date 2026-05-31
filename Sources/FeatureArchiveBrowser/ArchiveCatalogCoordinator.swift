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
        let metadata = (try? songMetadataStore?.loadAll()) ?? [:]
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
    ) -> (songs: [Song], scannedAt: Date)? {
        guard let archiveIndexStore else { return nil }
        guard let snapshot = try? archiveIndexStore.loadLatest() else { return nil }
        guard snapshot.matchesCurrentRoots(roots), !snapshot.songs.isEmpty else { return nil }
        let songs = mergeUserMetadata(into: snapshot.songs, collaborators: collaborators)
        return (songs, snapshot.scannedAt)
    }

    func persistCachedIndex(roots: [URL], songs: [Song], scannedAt: Date) {
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

    func persistUserMetadata(for songs: [Song]) {
        guard let songMetadataStore, !songs.isEmpty else { return }
        let items = songs.map { SongUserMetadata.from(song: $0) }
        do {
            try songMetadataStore.upsertAll(items)
        } catch {
            diagnostics.log(.error, "Song metadata save failed: \(error)")
        }
    }

}

extension ArchiveCatalogCoordinator {
    enum MetadataRankingRefresh {
        case none
        case previewAuto
        case cprAuto
    }

    func mergedSongAfterMetadataEdit(
        for song: Song,
        in songs: [Song],
        collaborators: [Collaborator],
        rankingRefresh: MetadataRankingRefresh = .none,
        mutate: (inout SongUserMetadata, inout Song) -> Void
    ) -> Song? {
        guard var scanned = songs.first(where: { $0.id == song.id }) else { return nil }
        var metadata = SongUserMetadata.from(song: scanned)
        mutate(&metadata, &scanned)

        switch rankingRefresh {
        case .none:
            break
        case .previewAuto:
            let context = PreviewRankingProjectContext.from(projectVersions: scanned.projectVersions)
            let ranker = PreviewConfidenceRanker()
            let ranked = ranker.rank(scanned.previewCandidates, projectContext: context)
            scanned.previewCandidates = ranked
            scanned.mainPreviewCandidateID = ranker.mainPreviewID(from: ranked)
        case .cprAuto:
            let detector = CPRVersionDetector()
            scanned.latestCPR = detector.latestCPR(from: scanned.projectVersions)
        }

        let map = Dictionary(uniqueKeysWithValues: collaborators.map { ($0.id, $0) })
        return ArchiveMetadataMerger.merge(
            scanned: scanned,
            metadata: metadata,
            collaboratorsByID: map
        )
    }
}
