import Foundation

/// Test double that simulates watcher startup failure.
public final class FailingArchiveRootWatcher: ArchiveRootWatching, @unchecked Sendable {
    public init() {}

    public func setRoots(_ roots: [URL], onChange: @escaping @MainActor (ArchiveRootWatchEvent) -> Void) -> Bool {
        false
    }

    public func stop() {}
}
