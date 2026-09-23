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
    func testPathOverflowInsideSongFoldersCoalescesToThoseFolders() async throws {
        let root = URL(fileURLWithPath: "/Volumes/Fixture Archive", isDirectory: true)
        let watcher = FSEventsArchiveRootWatcher(
            debounceInterval: 0.01,
            eventQueue: DispatchQueue(label: "watcher-coalesce"),
            maximumPendingPathCount: 4
        )
        let delivery = DeliveryProbe()
        XCTAssertTrue(watcher.setRoots([root]) { event in
            delivery.record(event)
        })
        defer { watcher.stop() }

        // A Cubase export storm: many files inside two songs plus one root-level project.
        let storm = (0..<40).map { "\(root.path)/Song A/Audio/Take \($0).wav" }
            + (0..<40).map { "\(root.path)/Song B/Mixdown/Bounce \($0).wav" }
            + ["\(root.path)/Loose.cpr"]
        watcher.simulateFSEventBatch(paths: storm, eventFlags: [])
        try await waitForDelivery(delivery)

        XCTAssertEqual(delivery.events.count, 1)
        XCTAssertEqual(delivery.paths.map(\.path), [
            "\(root.path)/Loose.cpr",
            "\(root.path)/Song A",
            "\(root.path)/Song B"
        ])
    }

    @MainActor
    func testCoalescedOverflowAcrossTooManySongFoldersRequestsFullRescan() async throws {
        let root = URL(fileURLWithPath: "/Volumes/Fixture Archive", isDirectory: true)
        let watcher = FSEventsArchiveRootWatcher(
            debounceInterval: 0.01,
            eventQueue: DispatchQueue(label: "watcher-coalesce-overflow"),
            maximumPendingPathCount: 4
        )
        let delivery = DeliveryProbe()
        XCTAssertTrue(watcher.setRoots([root]) { event in
            delivery.record(event)
        })
        defer { watcher.stop() }

        watcher.simulateFSEventBatch(
            paths: (0..<6).map { "\(root.path)/Song \($0)/Song \($0).cpr" },
            eventFlags: []
        )
        try await waitForDelivery(delivery)

        XCTAssertEqual(delivery.events, [.fullRescanRequired])
    }

    @MainActor
    func testVolumeAndRootEventsRequestFullRescanEvenInsideCoalescedStorm() async throws {
        let root = URL(fileURLWithPath: "/Volumes/Fixture Archive", isDirectory: true)
        let volumeFlags = [
            FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged),
            FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount),
            FSEventStreamEventFlags(kFSEventStreamEventFlagMount)
        ]
        for flag in volumeFlags {
            for pathCount in [1, 1_100] {
                let watcher = FSEventsArchiveRootWatcher(debounceInterval: 0.01)
                let delivery = DeliveryProbe()
                XCTAssertTrue(watcher.setRoots([root]) { event in
                    delivery.record(event)
                })
                let paths = (0..<pathCount).map { "\(root.path)/Song/Take \($0).wav" }
                var flags = Array(repeating: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified), count: pathCount)
                flags[pathCount - 1] = flag
                watcher.simulateFSEventBatch(paths: paths, eventFlags: flags)
                try await waitForDelivery(delivery)

                XCTAssertEqual(delivery.events, [.fullRescanRequired], "flag \(flag), \(pathCount) paths")
                watcher.stop()
            }
        }
    }

    func testSongFolderPathUsesDeepestRootAndKeepsItsSpelling() {
        let prefixes = ["/var/a", "/private/var/a", "/var/a/nested"]
        XCTAssertEqual(
            FSEventsArchiveRootWatcher.songFolderPath(containing: "/private/var/a/Song/x.cpr", rootPrefixes: prefixes),
            "/private/var/a/Song"
        )
        XCTAssertEqual(
            FSEventsArchiveRootWatcher.songFolderPath(containing: "/var/a/nested/Song/Mixdown/x.wav", rootPrefixes: prefixes),
            "/var/a/nested/Song"
        )
        XCTAssertEqual(FSEventsArchiveRootWatcher.songFolderPath(containing: "/var/a", rootPrefixes: prefixes), "/var/a")
        XCTAssertNil(FSEventsArchiveRootWatcher.songFolderPath(containing: "/var/ab/Song", rootPrefixes: prefixes))
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
