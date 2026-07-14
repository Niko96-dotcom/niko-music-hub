import Foundation
import XCTest
@testable import NikoMusicCore

final class LocalVaultRestoreEngineTests: XCTestCase {
    func testRestoreAcceptsVerifiedGenerationAfterOnlineOnlyTransition() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        var onlineOnlyRecord = fixture.archiveRecord
        onlineOnlyRecord.state = .archivedOnlineOnly
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: onlineOnlyRecord),
            store: store,
            provider: VaultRestoreProviderSpy(events: events),
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: workspace)
        )

        let result = try await engine.restoreAndOpen(
            projectID: fixture.projectID,
            destinationRelativePath: "Restored/Online Only Song"
        )

        XCTAssertNotNil(result.completedAt)
        XCTAssertEqual(workspace.opened.map(\.lastPathComponent), ["Synthetic Song.cpr"])
    }

    func testVaultRestoreOneActionMaterializesVerifiesPersistsThenSafelyOpensAndRetainsArchive() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let archiveBefore = try fixture.snapshot(at: fixture.generation)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(events: events)
        let catalog = VaultRestoreCatalogSpy(events: events)
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let opener = VaultRestorePersistCheckingOpener(store: store, workspace: workspace, events: events)
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store,
            provider: provider,
            catalog: catalog,
            projectOpener: opener
        )

        let result = try await engine.restoreAndOpen(
            projectID: fixture.projectID,
            destinationRelativePath: "Restored/Synthetic Song"
        )

        XCTAssertNotNil(result.completedAt)
        XCTAssertTrue(result.catalogLocationPersisted)
        XCTAssertEqual(provider.materializeCount, 1)
        XCTAssertEqual(catalog.locations.map(\.relativePath), ["Restored/Synthetic Song"])
        XCTAssertEqual(workspace.opened.map(\.lastPathComponent), ["Synthetic Song.cpr"])
        XCTAssertEqual(opener.persistedPhaseAtOpen, .openingInCubase)
        XCTAssertEqual(opener.catalogWasPersistedAtOpen, true)
        XCTAssertLessThan(try XCTUnwrap(events.firstIndex(of: "catalog")), try XCTUnwrap(events.firstIndex(of: "open")))
        try VaultManifestBuilder().verify(fixture.manifest, at: result.destinationURL)
        XCTAssertEqual(try fixture.snapshot(at: result.destinationURL), archiveBefore)
        XCTAssertEqual(try fixture.snapshot(at: fixture.generation), archiveBefore, "restore must retain the verified archive generation")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.generation.path))
        XCTAssertTrue(try store.recoverableRestoreRecords().isEmpty)
    }

    func testVaultRestoreOccupiedDestinationFailsClosedWithoutCatalogUpdateOrOpen() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let archiveBefore = try fixture.snapshot(at: fixture.generation)
        let occupied = fixture.active.appendingPathComponent("Restored/Synthetic Song", isDirectory: true)
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
        let sentinel = occupied.appendingPathComponent("keep.txt")
        try Data("occupied".utf8).write(to: sentinel)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let catalog = VaultRestoreCatalogSpy(events: events)
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store,
            provider: VaultRestoreProviderSpy(events: events),
            catalog: catalog,
            projectOpener: SafeVaultProjectOpener(workspace: workspace)
        )

        do {
            _ = try await engine.restoreAndOpen(projectID: fixture.projectID, destinationRelativePath: "Restored/Synthetic Song")
            XCTFail("expected occupied destination refusal")
        } catch {
            XCTAssertEqual(error as? LocalVaultRestoreError, .occupiedDestination)
        }

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("occupied".utf8))
        XCTAssertEqual(try fixture.snapshot(at: fixture.generation), archiveBefore)
        XCTAssertTrue(catalog.locations.isEmpty)
        XCTAssertTrue(workspace.opened.isEmpty)
        let interrupted = try XCTUnwrap(try store.recoverableRestoreRecords().first)
        XCTAssertEqual(interrupted.phase, .promotingActiveCopy)
        XCTAssertNotNil(interrupted.error)
    }

    func testVaultRestoreEachPersistedPhaseRecoversIdempotentlyAfterInterruption() async throws {
        for faultPoint in VaultRestoreFaultPoint.allCases {
            let fixture = try VaultRestoreFixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            let capture = VaultRestoreRecordCapture()
            let events = VaultRestoreEventLog()
            let interruptedEngine = LocalVaultRestoreEngine(
                activeRoot: fixture.active,
                activeRootID: fixture.activeRootID,
                resolver: VaultRestoreResolver(record: fixture.archiveRecord),
                store: store,
                provider: VaultRestoreProviderSpy(events: events),
                catalog: VaultRestoreCatalogSpy(events: events),
                projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
                faultInjector: { observed, record in
                    guard observed == faultPoint else { return }
                    capture.record = record
                    capture.persisted = try store.restoreRecord(id: record.id)
                    throw VaultTransferInterruption()
                }
            )

            do {
                _ = try await interruptedEngine.restoreAndOpen(
                    projectID: fixture.projectID,
                    destinationRelativePath: "Recovered/Synthetic Song"
                )
                XCTFail("expected interruption at \(faultPoint)")
            } catch is VaultTransferInterruption {}

            let interrupted = try XCTUnwrap(capture.record)
            XCTAssertEqual(capture.persisted?.phase, interrupted.phase, "phase must be durable before \(faultPoint)")
            let recoveryWorkspace = VaultRestoreWorkspaceSpy(events: events)
            let recovery = LocalVaultRestoreEngine(
                activeRoot: fixture.active,
                activeRootID: fixture.activeRootID,
                resolver: VaultRestoreResolver(record: fixture.archiveRecord),
                store: store,
                provider: VaultRestoreProviderSpy(events: events),
                catalog: VaultRestoreCatalogSpy(events: events),
                projectOpener: SafeVaultProjectOpener(workspace: recoveryWorkspace)
            )

            let first = await recovery.recoverAtLaunch()
            XCTAssertEqual(first.count, 1, "recovery result at \(faultPoint)")
            XCTAssertNotNil(first.first?.completedAt, "recovery completion at \(faultPoint)")
            XCTAssertEqual(recoveryWorkspace.opened.count, 1, "open exactly once during recovery at \(faultPoint)")
            try VaultManifestBuilder().verify(fixture.manifest, at: fixture.active.appendingPathComponent("Recovered/Synthetic Song"))
            let second = await recovery.recoverAtLaunch()
            XCTAssertTrue(second.isEmpty, "completed restore must not replay at \(faultPoint)")
        }
    }
}

private struct VaultRestoreResolver: VaultArchiveGenerationResolving {
    let record: VaultTransferRecord?

    func verifiedArchiveGeneration(projectID: ProjectID) throws -> VaultTransferRecord? {
        record?.projectID == projectID ? record : nil
    }
}

private final class VaultRestoreProviderSpy: ArchiveStorageProvider, @unchecked Sendable {
    private let lock = NSLock()
    private let events: VaultRestoreEventLog
    private var storedMaterializeCount = 0

    init(events: VaultRestoreEventLog) { self.events = events }

    var materializeCount: Int { lock.withLock { storedMaterializeCount } }
    func capabilities() async throws -> StorageCapabilities { .init(waitsForDurability: false, supportsMaterialization: true, supportsEviction: false) }
    func prepareForRead(_ location: URL) async throws { events.append("prepare") }
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws {
        lock.withLock { storedMaterializeCount += 1 }
        events.append("materialize")
    }
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

private final class VaultRestoreCatalogSpy: ActiveProjectLocationPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private let events: VaultRestoreEventLog
    private var storedLocations: [ProjectLocation] = []

    init(events: VaultRestoreEventLog) { self.events = events }
    var locations: [ProjectLocation] { lock.withLock { storedLocations } }

    func persistActiveLocation(projectID: ProjectID, location: ProjectLocation) throws {
        lock.withLock { storedLocations.append(location) }
        events.append("catalog")
    }
}

private final class VaultRestoreWorkspaceSpy: WorkspaceOpening, @unchecked Sendable {
    private let lock = NSLock()
    private let events: VaultRestoreEventLog
    private var storedOpened: [URL] = []

    init(events: VaultRestoreEventLog) { self.events = events }
    var opened: [URL] { lock.withLock { storedOpened } }

    func open(_ url: URL) -> Bool {
        lock.withLock { storedOpened.append(url) }
        events.append("open")
        return true
    }

    func revealInFinder(_ url: URL) {}
}

private final class VaultRestorePersistCheckingOpener: VaultProjectOpening, @unchecked Sendable {
    private let lock = NSLock()
    private let store: SQLiteVaultTransferStore
    private let opener: SafeVaultProjectOpener
    private let events: VaultRestoreEventLog
    private var storedPhase: VaultRestorePhase?
    private var storedCatalogFlag: Bool?

    init(store: SQLiteVaultTransferStore, workspace: VaultRestoreWorkspaceSpy, events: VaultRestoreEventLog) {
        self.store = store
        self.opener = SafeVaultProjectOpener(workspace: workspace)
        self.events = events
    }

    var persistedPhaseAtOpen: VaultRestorePhase? { lock.withLock { storedPhase } }
    var catalogWasPersistedAtOpen: Bool? { lock.withLock { storedCatalogFlag } }

    func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult? {
        let record = try store.recoverableRestoreRecords().first { $0.destinationURL == projectURL }
        lock.withLock {
            storedPhase = record?.phase
            storedCatalogFlag = record?.catalogLocationPersisted
        }
        events.append("persisted-before-open")
        return try opener.openProject(at: projectURL, allowedRoot: allowedRoot)
    }
}

private final class VaultRestoreEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) { lock.withLock { values.append(value) } }
    func firstIndex(of value: String) -> Int? { lock.withLock { values.firstIndex(of: value) } }
}

private final class VaultRestoreRecordCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRecord: VaultRestoreRecord?
    private var storedPersisted: VaultRestoreRecord?

    var record: VaultRestoreRecord? {
        get { lock.withLock { storedRecord } }
        set { lock.withLock { storedRecord = newValue } }
    }
    var persisted: VaultRestoreRecord? {
        get { lock.withLock { storedPersisted } }
        set { lock.withLock { storedPersisted = newValue } }
    }
}

private struct VaultRestoreFixture {
    let root: URL
    let active: URL
    let generation: URL
    let databaseURL: URL
    let activeRootID = UUID()
    let projectID = ProjectID()
    let manifest: VaultManifest
    let archiveRecord: VaultTransferRecord

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-restore-\(UUID().uuidString)", isDirectory: true)
        let active = root.appendingPathComponent("Active", isDirectory: true)
        let generation = root.appendingPathComponent("Archive/generations/verified", isDirectory: true)
        try FileManager.default.createDirectory(at: generation.appendingPathComponent("Audio", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try Data("cubase-project".utf8).write(to: generation.appendingPathComponent("Synthetic Song.cpr"))
        try Data((0..<4096).map { UInt8($0 % 251) }).write(to: generation.appendingPathComponent("Audio/take.wav"))
        let manifest = try VaultManifestBuilder().build(at: generation)
        var archiveRecord = VaultTransferRecord(
            projectID: projectID,
            sourceURL: active.appendingPathComponent("former-active"),
            stagingURL: root.appendingPathComponent("Archive/.niko-staging/old"),
            destinationURL: generation,
            state: .archiveVerified
        )
        archiveRecord.manifestID = manifest.id
        archiveRecord.manifest = manifest
        archiveRecord.durability = .verifiedLocal
        self.root = root
        self.active = active
        self.generation = generation
        self.databaseURL = root.appendingPathComponent("State/vault.sqlite")
        self.manifest = manifest
        self.archiveRecord = archiveRecord
    }

    func snapshot(at folder: URL) throws -> [String: Data] {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        let folderComponents = folder.standardizedFileURL.pathComponents
        var result: [String: Data] = [:]
        while let url = enumerator?.nextObject() as? URL {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                let relativePath = url.standardizedFileURL.pathComponents
                    .dropFirst(folderComponents.count)
                    .joined(separator: "/")
                result[relativePath] = try Data(contentsOf: url)
            }
        }
        return result
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
