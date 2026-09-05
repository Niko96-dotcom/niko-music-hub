import Foundation

protocol ArchiveBrowseProjecting: Sendable {
    func project(_ state: ArchiveBrowseState) async -> ArchiveBrowseResult?
}

/// Serial isolation keeps expensive live searches off the main actor without
/// running an unbounded set of searches when typing outruns a large catalog.
actor ArchiveBrowseProjector: ArchiveBrowseProjecting {
    func project(_ state: ArchiveBrowseState) -> ArchiveBrowseResult? {
        guard !Task.isCancelled else { return nil }
        return ArchiveBrowseProjection.project(state)
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
