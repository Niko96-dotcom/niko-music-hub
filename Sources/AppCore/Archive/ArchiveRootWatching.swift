import Foundation

/// A debounced archive-root filesystem change.
///
/// `fullRescanRequired` is intentionally distinct from a root-path change: it
/// means exact event paths were lost or exceeded the watcher budget, so an
/// incremental scan would be incomplete.
public enum ArchiveRootWatchEvent: Sendable, Equatable {
    case paths([URL])
    case fullRescanRequired
}

public protocol ArchiveRootWatching: Sendable {
    /// Observe `roots`; call `onChange` on the main queue after debounced filesystem events.
    /// A `fullRescanRequired` event is a correctness fallback when the watcher
    /// cannot provide a complete bounded path batch.
    /// Returns `false` when the watcher could not start (for example FSEventStreamCreate failed).
    @discardableResult
    func setRoots(_ roots: [URL], onChange: @escaping @MainActor (ArchiveRootWatchEvent) -> Void) -> Bool
    func stop()
}

/// Test double — no filesystem events.
public struct NoopArchiveRootWatcher: ArchiveRootWatching, Sendable {
    public init() {}

    public func setRoots(_ roots: [URL], onChange: @escaping @MainActor (ArchiveRootWatchEvent) -> Void) -> Bool { true }

    public func stop() {}
}
