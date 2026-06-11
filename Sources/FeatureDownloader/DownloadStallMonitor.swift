import Foundation

public protocol DownloadStallClock: Sendable {
    var now: Date { get }
}

public struct SystemDownloadStallClock: DownloadStallClock {
    public init() {}

    public var now: Date { Date() }
}

public final class DownloadStallMonitor: @unchecked Sendable {
    public static let stallWindowSeconds: TimeInterval = 120
    public static let stallErrorMessage = "Download stalled — no progress for 2 minutes"

    private let clock: any DownloadStallClock
    private let lock = NSLock()
    private var lastActivity: Date

    public init(clock: any DownloadStallClock = SystemDownloadStallClock()) {
        self.clock = clock
        self.lastActivity = clock.now
    }

    public func recordActivity() {
        lock.withLock {
            lastActivity = clock.now
        }
    }

    public func checkStalled() -> Bool {
        lock.withLock {
            clock.now.timeIntervalSince(lastActivity) >= Self.stallWindowSeconds
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
