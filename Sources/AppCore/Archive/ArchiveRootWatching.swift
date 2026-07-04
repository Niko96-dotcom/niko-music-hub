import Foundation

public protocol ArchiveRootWatching: Sendable {
    /// Observe `roots`; call `onChange` on the main queue after debounced filesystem events.
    func setRoots(_ roots: [URL], onChange: @escaping @MainActor ([URL]) -> Void)
    func stop()
}

/// Test double — no filesystem events.
public struct NoopArchiveRootWatcher: ArchiveRootWatching, Sendable {
    public init() {}

    public func setRoots(_ roots: [URL], onChange: @escaping @MainActor ([URL]) -> Void) {}

    public func stop() {}
}
