import Foundation

/// Symlink resolution used by path-safety and archive-scan code. Each resolution walks the path
/// on disk component by component, which is a round trip per component on external and network
/// volumes, so scan-cost tests count them: bind `counter` for the duration of a scan. Production
/// leaves it nil.
enum PathResolutionProbe {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        var count: Int { lock.withLock { value } }

        func increment() { lock.withLock { value += 1 } }
    }

    @TaskLocal static var counter: Counter?

    static func resolvingSymlinks(_ url: URL) -> URL {
        counter?.increment()
        return url.resolvingSymlinksInPath()
    }
}
