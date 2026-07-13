@testable import AppCore
import Foundation
import XCTest

final class FSEventsArchiveRootWatcherTests: XCTestCase {
    func testStartFailureReturnsFalseAndWatcherDeallocates() {
        weak var weakWatcher: FSEventsArchiveRootWatcher?
        autoreleasepool {
            let watcher = FSEventsArchiveRootWatcher(
                debounceInterval: 0,
                eventQueue: DispatchQueue(label: "watcher-start-failure"),
                streamStarter: { _ in false }
            )
            weakWatcher = watcher
            XCTAssertFalse(watcher.setRoots([FileManager.default.temporaryDirectory]) { _ in })
        }
        XCTAssertNil(weakWatcher)
    }

    func testRepeatedStartStopDoesNotRetainWatcher() {
        weak var weakWatcher: FSEventsArchiveRootWatcher?
        autoreleasepool {
            let watcher = FSEventsArchiveRootWatcher(debounceInterval: 0.01)
            weakWatcher = watcher
            for _ in 0..<25 {
                _ = watcher.setRoots([FileManager.default.temporaryDirectory]) { _ in }
                watcher.stop()
            }
        }
        XCTAssertNil(weakWatcher)
    }

    @MainActor
    func testStopSuppressesQueuedDebouncedDelivery() async throws {
        let watcher = FSEventsArchiveRootWatcher(debounceInterval: 0.05)
        let delivery = DeliveryProbe()
        XCTAssertTrue(watcher.setRoots([FileManager.default.temporaryDirectory]) { paths in
            delivery.record(paths)
        })

        watcher.simulateChangedPaths(["/tmp/should-not-deliver"])
        watcher.stop()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(delivery.count, 0)
    }

    @MainActor
    func testDebounceCoalescesAndSortsPaths() async throws {
        let watcher = FSEventsArchiveRootWatcher(debounceInterval: 0.01)
        let delivery = DeliveryProbe()
        XCTAssertTrue(watcher.setRoots([FileManager.default.temporaryDirectory]) { paths in
            delivery.record(paths)
        })
        defer { watcher.stop() }

        watcher.simulateChangedPaths(["/tmp/b", "/tmp/a", "/tmp/b"])
        for _ in 0..<100 where delivery.count == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(delivery.paths.map(\.path), ["/tmp/a", "/tmp/b"])
        XCTAssertEqual(delivery.count, 1)
    }
}

@MainActor
private final class DeliveryProbe {
    private(set) var count = 0
    private(set) var paths: [URL] = []

    func record(_ paths: [URL]) {
        count += 1
        self.paths = paths
    }
}
