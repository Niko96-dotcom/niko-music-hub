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
