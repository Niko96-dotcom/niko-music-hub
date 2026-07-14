import Foundation
import XCTest
@testable import NikoMusicCore

final class LocalVaultTransferEngineTests: XCTestCase {
    func testCompleteCopyPromotesVersionedVerifiedGenerationAndKeepsActiveBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.snapshotSource()
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(activeRoot: fixture.active, archiveRoot: fixture.archive, store: store)

        let record = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)

        XCTAssertEqual(record.state, .archiveVerified)
        XCTAssertEqual(record.durability, .verifiedLocal)
        XCTAssertTrue(record.destinationURL.path.contains("/generations/"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.stagingURL.path))
        try VaultManifestBuilder().verify(XCTUnwrap(record.manifest), at: record.destinationURL)
        XCTAssertEqual(try fixture.snapshotSource(), original)
    }

    func testLocalFolderProviderReportsOnlyVerifiedLocalDurability() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let provider = LocalFolderArchiveStorage(root: fixture.archive)

        let durability = try await provider.waitUntilDurable(fixture.archive)
        let eviction = try await provider.evictIfSupported(fixture.archive)
        let capabilities = try await provider.capabilities()
        XCTAssertEqual(durability, .verifiedLocal)
        XCTAssertEqual(eviction, .unsupported)
        XCTAssertFalse(capabilities.waitsForDurability)
    }

    func testProviderDurabilityBarrierRunsAgainAfterGenerationPromotion() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let provider = PromotionDurabilityProvider(archiveRoot: fixture.archive)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider
        )

        let record = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
        let barrierCount = await provider.barrierCount()
        let sawPromotedGeneration = await provider.sawPromotedGenerationAtFinalBarrier()

        XCTAssertEqual(record.state, .archiveVerified)
        XCTAssertEqual(record.durability, .syncedToProvider)
        XCTAssertEqual(barrierCount, 2)
        XCTAssertTrue(sawPromotedGeneration)
    }

    func testOccupiedGenerationIsNeverOverwrittenAndRequiresRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.snapshotSource()
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let capture = RecordCapture()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            faultInjector: { point, record in
                guard point == .promotingArchiveGeneration else { return }
                capture.record = record
                throw VaultTransferInterruption()
            }
        )
        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("expected interruption")
        } catch is VaultTransferInterruption {}
        let interrupted = try XCTUnwrap(capture.record)
        try FileManager.default.createDirectory(at: interrupted.destinationURL, withIntermediateDirectories: true)
        let sentinel = interrupted.destinationURL.appendingPathComponent("do-not-overwrite.txt")
        try Data("occupied".utf8).write(to: sentinel)

        let recovery = try LocalVaultTransferEngine(activeRoot: fixture.active, archiveRoot: fixture.archive, store: store)
        let results = await recovery.recoverAtLaunch()

        XCTAssertEqual(results.first?.state, .recoveryRequired)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("occupied".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: interrupted.stagingURL.path))
        XCTAssertEqual(try fixture.snapshotSource(), original)
    }

    func testEachFaultPointIsPersistedBeforeItsSideEffectAndLaunchRecoveryIsIdempotent() async throws {
        for point in VaultTransferFaultPoint.allCases {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let original = try fixture.snapshotSource()
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            let capture = RecordCapture()
            let engine = try LocalVaultTransferEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                store: store,
                faultInjector: { observedPoint, record in
                    guard observedPoint == point else { return }
                    capture.record = record
                    capture.persisted = try store.record(id: record.id)
                    throw VaultTransferInterruption()
                }
            )
            do {
                _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
                XCTFail("expected interruption at \(point)")
            } catch is VaultTransferInterruption {}

            let interrupted = try XCTUnwrap(capture.record)
            XCTAssertEqual(capture.persisted?.state, interrupted.state, "persisted before \(point)")
            XCTAssertEqual(try fixture.snapshotSource(), original, "Active changed at \(point)")
            if point == .copyingToArchiveStaging {
                XCTAssertFalse(FileManager.default.fileExists(atPath: interrupted.stagingURL.path))
            }
            if point == .promotingArchiveGeneration {
                XCTAssertFalse(FileManager.default.fileExists(atPath: interrupted.destinationURL.path))
            }

            let recovery = try LocalVaultTransferEngine(activeRoot: fixture.active, archiveRoot: fixture.archive, store: store)
            let firstRecovery = await recovery.recoverAtLaunch()
            XCTAssertEqual(firstRecovery.first?.state, .archiveVerified, "recovery from \(point)")
            XCTAssertEqual(try fixture.snapshotSource(), original, "Active changed recovering \(point)")
            let verified = try XCTUnwrap(firstRecovery.first)
            try VaultManifestBuilder().verify(XCTUnwrap(verified.manifest), at: verified.destinationURL)
            let secondRecovery = await recovery.recoverAtLaunch()
            XCTAssertTrue(secondRecovery.isEmpty, "terminal record selected after \(point)")
        }
    }
}

private actor PromotionDurabilityProvider: ArchiveStorageProvider {
    private let archiveRoot: URL
    private var barriers = 0
    private var sawPromotedGeneration = false

    init(archiveRoot: URL) { self.archiveRoot = archiveRoot }

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: true, supportsMaterialization: true, supportsEviction: true)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}

    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        barriers += 1
        if barriers == 2 {
            let generations = archiveRoot.appendingPathComponent("generations", isDirectory: true)
            let contents = (try? FileManager.default.contentsOfDirectory(at: generations, includingPropertiesForKeys: nil)) ?? []
            sawPromotedGeneration = !contents.isEmpty
        }
        return .syncedToProvider
    }

    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .evicted }
    func barrierCount() -> Int { barriers }
    func sawPromotedGenerationAtFinalBarrier() -> Bool { sawPromotedGeneration }
}

private final class RecordCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRecord: VaultTransferRecord?
    private var storedPersisted: VaultTransferRecord?

    var record: VaultTransferRecord? {
        get { lock.withLock { storedRecord } }
        set { lock.withLock { storedRecord = newValue } }
    }

    var persisted: VaultTransferRecord? {
        get { lock.withLock { storedPersisted } }
        set { lock.withLock { storedPersisted = newValue } }
    }
}

private struct Fixture {
    let root: URL
    let active: URL
    let archive: URL
    let source: URL
    let databaseURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("local-vault-transfer-\(UUID().uuidString)", isDirectory: true)
        active = root.appendingPathComponent("Active", isDirectory: true)
        archive = root.appendingPathComponent("Archive", isDirectory: true)
        source = active.appendingPathComponent("Artist Song", isDirectory: true)
        databaseURL = root.appendingPathComponent("state/vault.sqlite")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Audio", isDirectory: true), withIntermediateDirectories: true)
        try Data("cubase-project".utf8).write(to: source.appendingPathComponent("Artist Song.cpr"))
        try Data((0..<4096).map { UInt8($0 % 251) }).write(to: source.appendingPathComponent("Audio/take.wav"))
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
    }

    func snapshotSource() throws -> [String: Data] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: Array(keys))
        var result: [String: Data] = [:]
        while let url = enumerator?.nextObject() as? URL {
            if try url.resourceValues(forKeys: keys).isRegularFile == true {
                result[String(url.path.dropFirst(source.path.count + 1))] = try Data(contentsOf: url)
            }
        }
        return result
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
