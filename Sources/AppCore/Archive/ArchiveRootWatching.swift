import Foundation

public protocol ArchiveRootWatching: Sendable {
    /// Observe `roots`; call `onChange` on the main queue after debounced filesystem events.
    /// Returns `false` when the watcher could not start (for example FSEventStreamCreate failed).
    @discardableResult
    func setRoots(_ roots: [URL], onChange: @escaping @MainActor ([URL]) -> Void) -> Bool
    func stop()
}

/// Test double — no filesystem events.
public struct NoopArchiveRootWatcher: ArchiveRootWatching, Sendable {
    public init() {}

    public func setRoots(_ roots: [URL], onChange: @escaping @MainActor ([URL]) -> Void) -> Bool { true }

    public func stop() {}
}
