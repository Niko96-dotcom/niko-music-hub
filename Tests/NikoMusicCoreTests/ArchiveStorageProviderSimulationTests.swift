import XCTest
@testable import NikoMusicCore

private actor SimulatedArchiveStorageProvider: ArchiveStorageProvider {
    enum Behavior: Equatable, Sendable {
        case slowSync
        case offline
        case unsynced
        case evictionUnsupported
        case permissionLoss
    }

    enum SimulationError: Error, Equatable {
        case offline
        case unsynced
        case permissionLost
    }

    let behavior: Behavior
    private(set) var durabilityChecks = 0

    init(_ behavior: Behavior) { self.behavior = behavior }

    func capabilities() async throws -> StorageCapabilities {
        .init(
            waitsForDurability: true,
            supportsMaterialization: true,
            supportsEviction: behavior != .evictionUnsupported
        )
    }

    func prepareForRead(_ location: URL) async throws {
        if behavior == .offline { throw SimulationError.offline }
    }

    func prepareForWrite(at root: URL) async throws {
        if behavior == .permissionLoss { throw SimulationError.permissionLost }
    }

    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        durabilityChecks += 1
        switch behavior {
        case .slowSync where durabilityChecks == 1:
            throw SimulationError.unsynced
        case .offline:
            throw SimulationError.offline
        case .unsynced:
            throw SimulationError.unsynced
        case .permissionLoss:
            throw SimulationError.permissionLost
        case .slowSync, .evictionUnsupported:
            return .syncedToProvider
        }
    }

    func materialize(_ location: URL) async throws {
        if behavior == .offline { throw SimulationError.offline }
    }

    func evictIfSupported(_ location: URL) async throws -> EvictionResult {
        behavior == .evictionUnsupported ? .unsupported : .evicted
    }
}

final class ArchiveStorageProviderSimulationTests: XCTestCase {
    func testSlowSyncEventuallyReportsProviderDurability() async throws {
        let provider = SimulatedArchiveStorageProvider(.slowSync)
        do {
            _ = try await provider.waitUntilDurable(URL(fileURLWithPath: "/tmp/archive"))
            XCTFail("first check must remain unsynced")
        } catch {
            XCTAssertEqual(error as? SimulatedArchiveStorageProvider.SimulationError, .unsynced)
        }
        let durability = try await provider.waitUntilDurable(URL(fileURLWithPath: "/tmp/archive"))
        XCTAssertEqual(durability, .syncedToProvider)
    }

    func testOfflineFailsReadPreparationAndMaterialization() async {
        let provider = SimulatedArchiveStorageProvider(.offline)
        await assertSimulationError(.offline) { try await provider.prepareForRead(URL(fileURLWithPath: "/tmp/archive")) }
        await assertSimulationError(.offline) { try await provider.materialize(URL(fileURLWithPath: "/tmp/archive")) }
    }

    func testUnsyncedNeverClaimsDurability() async {
        let provider = SimulatedArchiveStorageProvider(.unsynced)
        await assertSimulationError(.unsynced) { _ = try await provider.waitUntilDurable(URL(fileURLWithPath: "/tmp/archive")) }
    }

    func testEvictionUnsupportedDegradesToArchivedLocal() async throws {
        let provider = SimulatedArchiveStorageProvider(.evictionUnsupported)
        let capabilities = try await provider.capabilities()
        XCTAssertFalse(capabilities.supportsEviction)
        let eviction = try await provider.evictIfSupported(URL(fileURLWithPath: "/tmp/archive"))
        XCTAssertEqual(eviction, .unsupported)
        XCTAssertEqual(
            VaultFailure(origin: .evictingProviderCache, reason: .evictionUnsupported).recoveryDecision,
            .keepArchiveLocal
        )
    }

    func testPermissionLossFailsClosedBeforeWriting() async {
        let provider = SimulatedArchiveStorageProvider(.permissionLoss)
        await assertSimulationError(.permissionLost) { try await provider.prepareForWrite(at: URL(fileURLWithPath: "/tmp/archive")) }
    }

    private func assertSimulationError(
        _ expected: SimulatedArchiveStorageProvider.SimulationError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("expected \(expected)")
        } catch {
            XCTAssertEqual(error as? SimulatedArchiveStorageProvider.SimulationError, expected)
        }
    }
}
