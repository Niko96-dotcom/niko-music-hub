import Foundation

public protocol ArchiveRootWatching: Sendable {
    /// Observe `roots`; call `onChange` on the main queue after debounced filesystem events.
    func setRoots(_ roots: [URL], onChange: @escaping @MainActor () -> Void)
    func stop()
}

/// Test double — no filesystem events.
public struct NoopArchiveRootWatcher: ArchiveRootWatching, Sendable {
    public init() {}

    public func setRoots(_ roots: [URL], onChange: @escaping @MainActor () -> Void) {}

    public func stop() {}
}
