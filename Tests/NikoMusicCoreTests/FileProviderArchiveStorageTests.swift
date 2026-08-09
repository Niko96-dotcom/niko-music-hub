import Darwin
import Foundation
import XCTest
@testable import NikoMusicCore

private actor StubFileProviderArchiveService: FileProviderArchiveServicing {
    enum Behavior: Sendable {
        case available
        case inspectionUnavailable
        case durabilityUnavailable
        case materializationUnavailable
        case evictionUnavailable
    }

    let behavior: Behavior
    private(set) var inspectedRoots: [URL] = []
    private(set) var durabilityRoots: [URL] = []
    private(set) var materializedRoots: [URL] = []
    private(set) var evictedRoots: [URL] = []

    init(_ behavior: Behavior = .available) {
        self.behavior = behavior
    }

    func inspect(root: URL) throws {
        inspectedRoots.append(root)
        if behavior == .inspectionUnavailable {
            throw FileProviderArchiveStorageError.managerUnavailable
        }
    }

    func waitForChanges(root: URL) throws {
        durabilityRoots.append(root)
        if behavior == .durabilityUnavailable {
            throw FileProviderArchiveStorageError.domainDisconnected
        }
    }

    func materialize(root: URL) throws {
        materializedRoots.append(root)
        if behavior == .materializationUnavailable {
            throw FileProviderArchiveStorageError.lookupUnavailable
        }
    }

    func evict(root: URL) throws {
        evictedRoots.append(root)
        if behavior == .evictionUnavailable {
            throw FileProviderArchiveStorageError.managerUnavailable
        }
    }
}

final class FileProviderArchiveStorageTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/provider-root", isDirectory: true)

    func testAvailableProviderReportsPublicCapabilities() async throws {
        let service = StubFileProviderArchiveService()
        let storage = FileProviderArchiveStorage(root: root, service: service)

        let capabilities = try await storage.capabilities()

        XCTAssertEqual(
            capabilities,
            StorageCapabilities(
                waitsForDurability: true,
                supportsMaterialization: true,
                supportsEviction: true
            )
        )
        let inspectedRoots = await service.inspectedRoots
        XCTAssertEqual(inspectedRoots, [root.standardizedFileURL])
    }

    func testUnavailableProviderStatusFailsClosed() async {
        let storage = FileProviderArchiveStorage(
            root: root,
            service: StubFileProviderArchiveService(.inspectionUnavailable)
        )

        do {
            _ = try await storage.capabilities()
            XCTFail("unavailable manager must not advertise provider capabilities")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .managerUnavailable)
        }
    }

    func testDurabilityRequiresSuccessfulProviderBarrier() async throws {
        let service = StubFileProviderArchiveService()
        let storage = FileProviderArchiveStorage(root: root, service: service)

        let durability = try await storage.waitUntilDurable(root)
        let durabilityRoots = await service.durabilityRoots
        XCTAssertEqual(durability, .syncedToProvider)
        XCTAssertEqual(durabilityRoots, [root.standardizedFileURL])
    }

    func testAmbiguousDurabilityNeverClaimsProviderSync() async {
        let storage = FileProviderArchiveStorage(
            root: root,
            service: StubFileProviderArchiveService(.durabilityUnavailable)
        )

        do {
            _ = try await storage.waitUntilDurable(root)
            XCTFail("ambiguous durability must fail closed")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .durabilityUnavailable)
        }
    }

    func testMaterializationRequestIsForwardedAndFailureIsVisible() async throws {
        let service = StubFileProviderArchiveService()
        let storage = FileProviderArchiveStorage(root: root, service: service)
        try await storage.materialize(root)
        let materializedRoots = await service.materializedRoots
        XCTAssertEqual(materializedRoots, [root.standardizedFileURL])

        let unavailable = FileProviderArchiveStorage(
            root: root,
            service: StubFileProviderArchiveService(.materializationUnavailable)
        )
        do {
            try await unavailable.materialize(root)
            XCTFail("failed materialization must remain a restore failure")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .materializationUnavailable)
        }
    }

    func testEvictionFailureClearlyDegradesToUnsupported() async throws {
        let service = StubFileProviderArchiveService(.evictionUnavailable)
        let storage = FileProviderArchiveStorage(root: root, service: service)

        let result = try await storage.evictIfSupported(root)
        let evictedRoots = await service.evictedRoots
        XCTAssertEqual(result, .unsupported)
        XCTAssertEqual(evictedRoots, [root.standardizedFileURL])
    }

    func testSuccessfulEvictionReportsEvicted() async throws {
        let storage = FileProviderArchiveStorage(
            root: root,
            service: StubFileProviderArchiveService()
        )
        let result = try await storage.evictIfSupported(root)
        XCTAssertEqual(result, .evicted)
    }

    func testReadinessPollingUsesBoundedExponentialBackoff() async throws {
        let probe = PollOutcomeProbe(outcomes: [false, false, false, true])
        let sleeper = PollDelayRecorder()
        let policy = FileProviderPollPolicy(
            timeout: .seconds(10),
            initialBackoff: .milliseconds(250),
            maximumBackoff: .seconds(5),
            maximumReadinessProbes: 8
        )

        try await FileProviderReadinessPoller.pollUntilReady(
            policy: policy,
            probe: { _ in await probe.next() },
            sleep: { delay in await sleeper.record(delay) }
        )

        let probeCount = await probe.count
        let recordedDelays = await sleeper.delays
        XCTAssertEqual(probeCount, 4)
        XCTAssertEqual(recordedDelays, [.milliseconds(250), .milliseconds(500), .seconds(1)])
    }

    func testReadinessPollingFailsClosedAtProbeCapWithoutTightLooping() async {
        let probe = PollOutcomeProbe(outcomes: [])
        let policy = FileProviderPollPolicy(
            timeout: .seconds(10),
            initialBackoff: .milliseconds(1),
            maximumBackoff: .milliseconds(4),
            maximumReadinessProbes: 3
        )

        do {
            try await FileProviderReadinessPoller.pollUntilReady(
                policy: policy,
                probe: { _ in await probe.next() },
                sleep: { _ in }
            )
            XCTFail("pending provider state must not loop forever")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .operationTimedOut)
        }
        let probeCount = await probe.count
        XCTAssertEqual(probeCount, 3)
    }

    func testProviderEnumerationStopsWhenTheOperationCanNoLongerContinue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<3 {
            try Data("fixture".utf8).write(to: root.appendingPathComponent("\(index).cpr"))
        }

        var continuationChecks = 0
        var visits = 0
        XCTAssertThrowsError(
            try SystemFileProviderArchiveService.forEachItem(
                fileManager: .default,
                at: root,
                keys: [.isRegularFileKey],
                shouldContinue: {
                    continuationChecks += 1
                    if continuationChecks >= 3 { throw FileProviderArchiveStorageError.operationTimedOut }
                }
            ) { _ in
                visits += 1
            }
        ) { error in
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .operationTimedOut)
        }
        XCTAssertLessThan(visits, 3)
    }

    func testSystemProviderEnumerationFailsClosedOnUnreadableSubtree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let blocked = root.appendingPathComponent("blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data("hidden".utf8).write(to: blocked.appendingPathComponent("hidden.cpr"))
        defer {
            chmod(blocked.path, S_IRWXU)
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertEqual(chmod(blocked.path, 0), 0)

        XCTAssertThrowsError(
            try SystemFileProviderArchiveService.forEachItem(
                fileManager: .default,
                at: root,
                keys: [.isRegularFileKey]
            ) { _ in }
        )
    }
}

private actor PollOutcomeProbe {
    private var outcomes: [Bool]
    private(set) var count = 0

    init(outcomes: [Bool]) {
        self.outcomes = outcomes
    }

    func next() -> Bool {
        count += 1
        return outcomes.isEmpty ? false : outcomes.removeFirst()
    }
}

private actor PollDelayRecorder {
    private(set) var delays: [Duration] = []

    func record(_ delay: Duration) {
        delays.append(delay)
    }
}
