import Foundation

/// Test double that invokes the watcher callback with explicit changed paths.
public final class TestArchiveRootWatcher: ArchiveRootWatching, @unchecked Sendable {
    private var onChange: (@MainActor (ArchiveRootWatchEvent) -> Void)?

    public init() {}

    public func setRoots(_ roots: [URL], onChange: @escaping @MainActor (ArchiveRootWatchEvent) -> Void) -> Bool {
        self.onChange = onChange
        return true
    }

    public func stop() {
        onChange = nil
    }

    public func simulateFilesystemChange(paths: [URL]) {
        guard let onChange else { return }
        Task { @MainActor in
            onChange(.paths(paths))
        }
    }

    /// Simulates an FSEvents overflow/drop where an incremental update would
    /// be incomplete and the consumer must run a full scan.
    public func simulateFilesystemOverflow() {
        guard let onChange else { return }
        Task { @MainActor in
            onChange(.fullRescanRequired)
        }
    }
}
