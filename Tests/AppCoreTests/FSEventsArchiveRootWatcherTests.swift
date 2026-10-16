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
    func testStopFromCallbackSuppressesAlreadyQueuedDelivery() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/watcher-reentrant-stop-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let eventQueue = DispatchQueue(label: "watcher-reentrant-stop")
        let watcher = FSEventsArchiveRootWatcher(debounceInterval: 0, eventQueue: eventQueue)
        let delivery = DeliveryProbe()
        let watchdog = reentrancyWatchdog("stop() did not return from onChange")
        defer {
            watcher.stop()
            watchdog.cancel()
        }
        XCTAssertTrue(watcher.setRoots([root]) { event in
            watcher.stop()
            delivery.record(event)
        })

        queueSeparateBatches(watcher, eventQueue: eventQueue, root: root)
        try await waitForDelivery(delivery)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(delivery.count, 1)
    }

    @MainActor
    func testReplaceRootsFromCallbackSuppressesOldGenerationAndDeliversNewEvents() async throws {
        let fixture = URL(fileURLWithPath: "/private/tmp/watcher-reentrant-roots-\(UUID())", isDirectory: true)
        let oldRoot = fixture.appendingPathComponent("old", isDirectory: true)
        let newRoot = fixture.appendingPathComponent("new", isDirectory: true)
        try FileManager.default.createDirectory(at: oldRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let eventQueue = DispatchQueue(label: "watcher-reentrant-roots")
        let watcher = FSEventsArchiveRootWatcher(debounceInterval: 0, eventQueue: eventQueue)
        let oldDelivery = DeliveryProbe()
        let newDelivery = DeliveryProbe()
        let newPath = newRoot.appendingPathComponent("Song.cpr").path
        let watchdog = reentrancyWatchdog("setRoots() did not return from onChange")
        defer {
            watcher.stop()
            watchdog.cancel()
        }
        XCTAssertTrue(watcher.setRoots([oldRoot]) { event in
            XCTAssertTrue(watcher.setRoots([newRoot]) { newEvent in
                newDelivery.record(newEvent)
            })
            oldDelivery.record(event)
            watcher.simulateChangedPaths([newPath])
        })

        queueSeparateBatches(watcher, eventQueue: eventQueue, root: oldRoot)
        try await waitForDelivery(newDelivery)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(oldDelivery.count, 1)
        XCTAssertEqual(newDelivery.count, 1)
        XCTAssertEqual(newDelivery.paths.map(\.path), [newPath])
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
    func testEmptyDebouncedBatchDoesNotSilenceLaterEvents() async throws {
        let watcher = FSEventsArchiveRootWatcher(debounceInterval: 0.01)
        let delivery = DeliveryProbe()
        XCTAssertTrue(watcher.setRoots([FileManager.default.temporaryDirectory]) { event in
            delivery.record(event)
        })
        defer { watcher.stop() }

        watcher.simulateUndecodableFSEventBatch()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(delivery.count, 0)

        watcher.simulateChangedPaths(["/tmp/after-empty-batch"])
        try await waitForDelivery(delivery)

        XCTAssertEqual(delivery.paths.map(\.path), ["/tmp/after-empty-batch"])
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

    func testStreamWatchesRootSoRootChangedEventsArrive() {
        let watchRoot = FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
        XCTAssertEqual(FSEventsArchiveRootWatcher.streamCreateFlags & watchRoot, watchRoot)
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

    @MainActor
    private func queueSeparateBatches(
        _ watcher: FSEventsArchiveRootWatcher,
        eventQueue: DispatchQueue,
        root: URL
    ) {
        // Keep MainActor occupied until two separate debounces have queued their
        // deliveries. The first callback must cancel admission of the second
        // queued delivery, rather than only cancelling an unfired debounce item.
        for name in ["first.cpr", "queued.cpr"] {
            watcher.simulateChangedPaths([root.appendingPathComponent(name).path])
            let queued = DispatchSemaphore(value: 0)
            eventQueue.asyncAfter(deadline: .now() + 0.05) { queued.signal() }
            XCTAssertEqual(queued.wait(timeout: .now() + 1), .success)
        }
    }

    private func reentrancyWatchdog(_ message: String) -> any DispatchSourceTimer {
        // XCTest async timeouts cannot fire while MainActor is deadlocked. This
        // independent queue terminates the test process with a failing exit if
        // reentrant cancellation blocks, so the runner cannot hang indefinitely.
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.setEventHandler { fatalError(message) }
        timer.schedule(deadline: .now() + 5)
        timer.resume()
        return timer
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
