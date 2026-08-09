@testable import AppCore
import CoreServices
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
        XCTAssertTrue(watcher.setRoots([FileManager.default.temporaryDirectory]) { event in
            delivery.record(event)
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
        XCTAssertTrue(watcher.setRoots([FileManager.default.temporaryDirectory]) { event in
            delivery.record(event)
        })
        defer { watcher.stop() }

        watcher.simulateChangedPaths(["/tmp/b", "/tmp/a", "/tmp/b"])
        for _ in 0..<100 where delivery.count == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(delivery.paths.map(\.path), ["/tmp/a", "/tmp/b"])
        XCTAssertEqual(delivery.count, 1)
    }

    @MainActor
    func testContinuousChangesDoNotPostponeDeliveryIndefinitely() async throws {
        let watcher = FSEventsArchiveRootWatcher(debounceInterval: 0.2)
        let delivery = DeliveryProbe()
        XCTAssertTrue(watcher.setRoots([FileManager.default.temporaryDirectory]) { event in
            delivery.record(event)
        })
        defer { watcher.stop() }

        watcher.simulateChangedPaths(["/tmp/0"])
        for index in 1...8 {
            try await Task.sleep(for: .milliseconds(25))
            watcher.simulateChangedPaths(["/tmp/\(index)"])
        }
        // A trailing-debounce reset would defer this until 200 ms after the
        // final event. A bounded coalescing window delivers the first batch
        // while events are still arriving.
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThanOrEqual(delivery.count, 1)
    }

    @MainActor
    func testPathOverflowRequestsFullRescanInsteadOfPartialPaths() async throws {
        let watcher = FSEventsArchiveRootWatcher(
            debounceInterval: 0.01,
            maximumPendingPathCount: 2
        )
        let delivery = DeliveryProbe()
        XCTAssertTrue(watcher.setRoots([FileManager.default.temporaryDirectory]) { event in
            delivery.record(event)
        })
        defer { watcher.stop() }

        watcher.simulateFSEventBatch(
            paths: ["/tmp/a", "/tmp/b", "/tmp/c"],
            eventFlags: []
        )
        try await waitForDelivery(delivery)

        XCTAssertEqual(delivery.events, [.fullRescanRequired])
        XCTAssertTrue(delivery.paths.isEmpty)
    }

    @MainActor
    func testDroppedFSEventRequestsFullRescan() async throws {
        let dropFlags = [
            FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs),
            FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped),
            FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
        ]

        for flag in dropFlags {
            let watcher = FSEventsArchiveRootWatcher(debounceInterval: 0.01)
            let delivery = DeliveryProbe()
            XCTAssertTrue(watcher.setRoots([FileManager.default.temporaryDirectory]) { event in
                delivery.record(event)
            })

            watcher.simulateFSEventBatch(paths: ["/tmp/ignored"], eventFlags: [flag])
            try await waitForDelivery(delivery)

            XCTAssertEqual(delivery.events, [.fullRescanRequired])
            watcher.stop()
        }
    }

    @MainActor
    private func waitForDelivery(_ delivery: DeliveryProbe) async throws {
        for _ in 0..<100 where delivery.count == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(delivery.count, 1)
    }
}

@MainActor
private final class DeliveryProbe {
    private(set) var count = 0
    private(set) var paths: [URL] = []
    private(set) var events: [ArchiveRootWatchEvent] = []

    func record(_ event: ArchiveRootWatchEvent) {
        count += 1
        events.append(event)
        if case .paths(let paths) = event {
            self.paths = paths
        }
    }
}
