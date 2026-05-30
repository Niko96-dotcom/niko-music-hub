import Foundation

/// Debounces browse list recomputation for live search typing (see ``ArchiveBrowserViewModel/setSearchQuery(_:immediate:)``).
@MainActor
final class ArchiveBrowseRefreshDriver {
    private var debounceTask: Task<Void, Never>?
    private static let debounceNanoseconds: UInt64 = 200_000_000

    func cancelPendingDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    func scheduleDebouncedBrowseRecompute(_ recompute: @escaping @MainActor () -> Void) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            recompute()
        }
    }
}
