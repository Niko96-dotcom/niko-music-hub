@testable import FeatureDownloader
import Foundation

final class FakeDownloadStallClock: DownloadStallClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock {
            current = current.addingTimeInterval(seconds)
        }
    }
}

final class LockedStringArray: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.downloaderTestWithLock {
            storage.append(value)
        }
    }

    func values() -> [String] {
        lock.downloaderTestWithLock { storage }
    }
}

extension NSLock {
    func downloaderTestWithLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
