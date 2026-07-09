import Foundation

/// Test double that invokes the watcher callback with explicit changed paths.
public final class TestArchiveRootWatcher: ArchiveRootWatching, @unchecked Sendable {
    private var onChange: (@MainActor ([URL]) -> Void)?

    public init() {}

    public func setRoots(_ roots: [URL], onChange: @escaping @MainActor ([URL]) -> Void) -> Bool {
        self.onChange = onChange
        return true
    }

    public func stop() {
        onChange = nil
    }

    public func simulateFilesystemChange(paths: [URL]) {
        guard let onChange else { return }
        Task { @MainActor in
            onChange(paths)
        }
    }
}
