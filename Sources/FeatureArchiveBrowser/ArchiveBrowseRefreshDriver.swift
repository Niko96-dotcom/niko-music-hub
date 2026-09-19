import Foundation
import NikoMusicCore

protocol ArchiveBrowseProjecting: Sendable {
    func project(_ state: ArchiveBrowseState) async -> ArchiveBrowseResult?
}

/// Serial isolation keeps expensive live searches off the main actor without
/// running an unbounded set of searches when typing outruns a large catalog.
/// Owns one reusable `MusicSearchIndex` incrementally synced to the latest
/// shelf: per-song field invalidation reuses normalization, removed ids are
/// dropped so memory stays bounded by the live shelf (no history cap, no
/// global cache). Empty queries never touch the index.
actor ArchiveBrowseProjector: ArchiveBrowseProjecting {
    private var cachedIndex = MusicSearchIndex()

    func project(_ state: ArchiveBrowseState) -> ArchiveBrowseResult? {
        guard !Task.isCancelled else { return nil }
        let trimmed = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            guard !Task.isCancelled else { return nil }
            return ArchiveBrowseProjection.project(state)
        }
        let onShelf = ArchiveBrowseProjection.shelfSongs(from: state)
        cachedIndex.sync(from: onShelf)
        guard !Task.isCancelled else { return nil }
        return ArchiveBrowseProjection.project(state, searchIndex: cachedIndex)
    }
}

/// Debounces and computes live search; immediate browse actions remain synchronous.
@MainActor
final class ArchiveBrowseRefreshDriver {
    private var debounceTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64
    private let projector: any ArchiveBrowseProjecting

    init(
        debounceNanoseconds: UInt64 = 200_000_000,
        projector: any ArchiveBrowseProjecting = ArchiveBrowseProjector()
    ) {
        self.debounceNanoseconds = debounceNanoseconds
        self.projector = projector
    }

    deinit { debounceTask?.cancel() }

    func cancelPendingDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    func scheduleDebouncedBrowseRecompute(
        snapshot: @escaping @MainActor () -> ArchiveBrowseState?,
        apply: @escaping @MainActor (ArchiveBrowseResult) -> Void
    ) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [projector, debounceNanoseconds] in
            do { try await Task.sleep(nanoseconds: debounceNanoseconds) }
            catch { return }
            guard !Task.isCancelled, let state = snapshot() else { return }
            guard let result = await projector.project(state), !Task.isCancelled else { return }
            // Cancellation and publication are checked together on the main actor.
            // A superseding query/catalog/root change cannot slip between them.
            apply(result)
        }
    }
}
