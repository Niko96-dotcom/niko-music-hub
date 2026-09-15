import Foundation
import XCTest
@testable import NikoMusicCore

final class VaultArchiveLayoutTests: XCTestCase {
    func testArchiveRestoreRoundTripPreservesProblemNamesAndDistinctSiblings() async throws {
        let fixture = try PortableArchiveFixture(siblings: true)
        defer { fixture.remove() }
        let before = try VaultManifestBuilder().build(at: fixture.source)
        let engine = try fixture.engine()
        let archived = try await engine.archive(projectID: fixture.projectID, sourceURL: fixture.source)
        let manifest = try XCTUnwrap(archived.manifest)
        XCTAssertEqual(manifest.archiveLayout, .portableNamesV1)
        XCTAssertTrue(before.hasSameImmutableContent(as: manifest), "storage names do not change the logical project")
        XCTAssertEqual(archived.state, .archiveVerified)
        try VaultManifestBuilder().verifyArchive(manifest, at: archived.destinationURL)
        try VaultManifestBuilder().verify(before, at: fixture.source)
        XCTAssertThrowsError(try VaultManifestBuilder().verify(manifest, at: archived.destinationURL), "a legacy reader fails closed")
        XCTAssertNotEqual(manifest.archiveRelativePath(for: "vocals DRYC "), "vocals DRYC")
        let decoded = try JSONDecoder().decode(VaultTransferRecord.self, from: JSONEncoder().encode(archived))
        XCTAssertEqual(decoded, archived)
        let restored = try await fixture.restore()
        XCTAssertNotNil(restored.completedAt)
        try VaultManifestBuilder().verify(before, at: restored.destinationURL)
        for path in fixture.files {
            XCTAssertEqual(try Data(contentsOf: fixture.source.appendingPathComponent(path)), try Data(contentsOf: restored.destinationURL.appendingPathComponent(path)), path)
        }
        let supplement = try VaultProjectionSupplementBuilder().build(at: archived.destinationURL, verifiedAgainst: manifest)
        try supplement.validate(against: manifest)
    }

    func testPortableArchiveResumesAfterInterruptionWithPersistedLayout() async throws {
        let fixture = try PortableArchiveFixture()
        defer { fixture.remove() }
        let interrupted = try fixture.engine(fault: { point, _ in
            if point == .awaitingProviderDurability { throw VaultTransferInterruption() }
        })
        do {
            _ = try await interrupted.archive(projectID: fixture.projectID, sourceURL: fixture.source)
            XCTFail("expected interruption")
        } catch is VaultTransferInterruption {}
        let pending = try XCTUnwrap(try fixture.store.recoverableRecords().first)
        XCTAssertEqual(pending.manifest?.archiveLayout, .portableNamesV1)
        let results = await (try fixture.engine()).recoverAtLaunch()
        XCTAssertEqual(results.map(\.state), [.archiveVerified])
        XCTAssertEqual(results.first?.id, pending.id)
        let restored = try await fixture.restore()
        try VaultManifestBuilder().verify(try XCTUnwrap(pending.manifest), at: restored.destinationURL)
    }

    func testExplicitLegacyRetryRetainsFailedCopyAndRestoresOriginalPaths() async throws {
        let fixture = try PortableArchiveFixture()
        defer { fixture.remove() }
        let failed = try fixture.legacyFailure()
        let retriedValue = await (try fixture.engine()).retryRecoverableTransfer(id: failed.id)
        let retried = try XCTUnwrap(retriedValue)
        XCTAssertEqual(retried.id, failed.id)
        XCTAssertEqual(retried.state, .archiveVerified)
        XCTAssertEqual(retried.manifest?.archiveLayout, .portableNamesV1)
        let retained = try XCTUnwrap(retried.preservedArchiveCopies?.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.appendingPathComponent("vocals DRYC/take.wav").path))
        XCTAssertEqual(try fixture.store.record(id: failed.id)?.preservedArchiveCopies, [retained])
        try VaultManifestBuilder().verify(try XCTUnwrap(failed.manifest), at: fixture.source)
        let restored = try await fixture.restore()
        try VaultManifestBuilder().verify(try XCTUnwrap(failed.manifest), at: restored.destinationURL)
    }

    func testLegacyRetryRejectsChangedSourceBeforeMovingAnyStaging() async throws {
        let fixture = try PortableArchiveFixture()
        defer { fixture.remove() }
        let failed = try fixture.legacyFailure()
        let stageBefore = try VaultManifestBuilder().build(at: failed.stagingURL)
        try Data("new vocal take".utf8).write(to: fixture.source.appendingPathComponent("vocals DRYC /take.wav"))
        let retried = await (try fixture.engine()).retryRecoverableTransfer(id: failed.id)
        XCTAssertEqual(retried?.state, .failedRecoverable)
        XCTAssertNil(retried?.preservedArchiveCopies)
        XCTAssertEqual(retried?.manifest, failed.manifest)
        XCTAssertTrue(retried?.error?.message.contains("changed") == true)
        try VaultManifestBuilder().verify(stageBefore, at: failed.stagingURL)
    }

    func testInterruptedLegacyUpgradeResumesWithoutDiscardingRetainedCopy() async throws {
        let fixture = try PortableArchiveFixture()
        defer { fixture.remove() }
        let failed = try fixture.legacyFailure()
        let interrupted = try fixture.engine(fault: { point, _ in
            if point == .copyingToArchiveStaging { throw VaultTransferInterruption() }
        })
        let pending = await interrupted.retryRecoverableTransfer(id: failed.id)
        XCTAssertEqual(pending?.state, .copyingToArchiveStaging)
        let retained = try XCTUnwrap(pending?.preservedArchiveCopies?.first)
        let retainedManifest = try VaultManifestBuilder().build(at: retained)
        let recovered = await (try fixture.engine()).recoverAtLaunch()
        XCTAssertEqual(recovered.map(\.id), [failed.id])
        XCTAssertEqual(recovered.first?.state, .archiveVerified)
        try VaultManifestBuilder().verify(retainedManifest, at: retained)
        try VaultManifestBuilder().verify(try XCTUnwrap(failed.manifest), at: fixture.source)
    }

    func testSourceChangeDuringUpgradeAdmissionStopsBeforeNewCopy() async throws {
        let fixture = try PortableArchiveFixture()
        defer { fixture.remove() }
        let failed = try fixture.legacyFailure()
        let sourceFile = fixture.source.appendingPathComponent("vocals DRYC /take.wav")
        let engine = try LocalVaultTransferEngine(activeRoot: fixture.active, archiveRoot: fixture.archive, store: fixture.store,
            writeAdmission: { _, operation in
                try await operation()
                try Data("changed during admission".utf8).write(to: sourceFile)
            })
        let stopped = await engine.retryRecoverableTransfer(id: failed.id)
        XCTAssertEqual(stopped?.state, .failedRecoverable)
        XCTAssertEqual(stopped?.manifest, failed.manifest)
        XCTAssertTrue(stopped?.error?.message.contains("changed") == true)
        let retained = try XCTUnwrap(stopped?.preservedArchiveCopies?.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.appendingPathComponent("vocals DRYC/take.wav").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.destinationURL.path))
    }

    func testCorruptEncodedArchiveCannotRestoreOrRemoveActive() async throws {
        let fixture = try PortableArchiveFixture()
        defer { fixture.remove() }
        let engine = try fixture.engine()
        let archived = try await engine.archive(projectID: fixture.projectID, sourceURL: fixture.source)
        let manifest = try XCTUnwrap(archived.manifest)
        let path = manifest.archiveRelativePath(for: "vocals DRYC /take.wav")
        try Data("WRONG".utf8).write(to: archived.destinationURL.appendingPathComponent(path))
        do { _ = try await fixture.restore(); XCTFail("corrupt archive must not restore") } catch {}
        do { _ = try await engine.removeActiveCopy(after: archived); XCTFail("corrupt archive must not authorize removal") } catch {}
        try VaultManifestBuilder().verify(manifest, at: fixture.source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.active.appendingPathComponent("Restored").path))
    }

    func testFileProviderUsesEncodedPathsForPromisedMetadata() async throws {
        let fixture = try PortableArchiveFixture()
        defer { fixture.remove() }
        let archived = try await (try fixture.engine()).archive(projectID: fixture.projectID, sourceURL: fixture.source)
        let service = PortableMetadataService()
        let provider = FileProviderArchiveStorage(root: fixture.archive, service: service)
        let locality = try await provider.currentLocality(at: archived.destinationURL, manifest: XCTUnwrap(archived.manifest))
        XCTAssertEqual(locality, .fullyLocalCurrent)
        let paths = await service.paths
        XCTAssertEqual(paths.count, fixture.files.count)
        XCTAssertTrue(paths.contains { $0.contains("~nmh1-") })
        XCTAssertFalse(paths.contains { $0.contains("vocals DRYC /") || $0.contains("\r") })
    }

    func testLegacyManifestDecodesWithoutLayoutAndFutureLayoutFailsClosed() throws {
        let fixture = try PortableArchiveFixture()
        defer { fixture.remove() }
        let legacy = try VaultManifestBuilder().build(at: fixture.source)
        let data = try JSONEncoder().encode(legacy)
        XCTAssertNil(try JSONDecoder().decode(VaultManifest.self, from: data).archiveLayout)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["archiveLayout"] = "future-version"
        XCTAssertThrowsError(try JSONDecoder().decode(VaultManifest.self, from: JSONSerialization.data(withJSONObject: object)))
    }
}

private struct PortableArchiveFixture {
    let root: URL
    let active: URL
    let archive: URL
    let source: URL
    let projectID = ProjectID()
    let store: SQLiteVaultTransferStore
    let files: [String]

    init(siblings: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("portable-archive-\(UUID().uuidString)").resolvingSymlinksInPath()
        active = root.appendingPathComponent("Active")
        archive = root.appendingPathComponent("Archive")
        source = active.appendingPathComponent("Synthetic")
        files = ["Synthetic.cpr", "vocals DRYC /take.wav", "Icon\r"]
            + (siblings ? ["vocals DRYC/take.wav", "~nmh1-literal/take.wav", "trailing./file.wav"] : [])
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        for (index, path) in files.enumerated() {
            let url = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("take\(index)".utf8).write(to: url)
        }
        store = try SQLiteVaultTransferStore(databaseURL: root.appendingPathComponent("state.sqlite"))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func engine(fault: LocalVaultTransferEngine.FaultInjector? = nil) throws -> LocalVaultTransferEngine {
        try LocalVaultTransferEngine(activeRoot: active, archiveRoot: archive, store: store,
            provider: PortableTestProvider(root: archive), faultInjector: fault,
            writeAdmission: { _, operation in try await operation() }, removalAdmission: { _ in })
    }

    func restore() async throws -> VaultRestoreRecord {
        let engine = LocalVaultRestoreEngine(activeRoot: active, archiveRoot: archive, activeRootID: UUID(),
            resolver: store, store: store, provider: PortableTestProvider(root: archive),
            catalog: PortableCatalog(), projectOpener: SafeVaultProjectOpener(workspace: nil),
            writeAdmission: { _, operation in try await operation() })
        return try await engine.restoreAndOpen(projectID: projectID, destinationRelativePath: "Restored")
    }

    func legacyFailure() throws -> VaultTransferRecord {
        let id = UUID()
        let staging = archive.appendingPathComponent(".niko-staging/\(projectID)/\(id.uuidString.lowercased())")
        let destination = archive.appendingPathComponent("generations/\(projectID)/generation-\(id.uuidString.lowercased())")
        try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: staging)
        try FileManager.default.moveItem(at: staging.appendingPathComponent("vocals DRYC "), to: staging.appendingPathComponent("vocals DRYC"))
        var record = VaultTransferRecord(id: id, projectID: projectID, sourceURL: source, stagingURL: staging, destinationURL: destination, state: .failedRecoverable)
        record.manifest = try VaultManifestBuilder().build(at: source)
        record.manifestID = record.manifest?.id
        record.retryCount = 5
        record.error = VaultTransferError(origin: .verifyingArchiveStaging, reason: .integrityMismatch, message: "provider rewrote a name")
        try store.save(record)
        return record
    }
}

private struct PortableCatalog: ActiveProjectLocationPersisting {
    func persistActiveLocation(projectID: ProjectID, location: ProjectLocation) throws {}
}

private struct PortableTestProvider: ArchiveStorageProvider {
    let root: URL
    func capabilities() async throws -> StorageCapabilities { .init(waitsForDurability: true, supportsMaterialization: false, supportsEviction: false) }
    func currentLocality(at location: URL, manifest: VaultManifest) async throws -> ArchiveStorageLocality { .fullyLocalCurrent }
    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: location, includingPropertiesForKeys: nil))
        while let url = walker.nextObject() as? URL {
            let name = url.lastPathComponent
            guard !name.hasSuffix(" "), !name.hasSuffix("."), !name.contains("\r") else {
                throw FileProviderArchiveStorageError.durabilityUnavailable
            }
        }
        return .syncedToProvider
    }
}

private actor PortableMetadataService: FileProviderArchiveServicing {
    var paths: [String] = []
    func inspect(root: URL) async throws {}
    func waitForChanges(root: URL) async throws {}
    func materialize(root: URL, expectedItems: [FileProviderExpectedItem]) async throws {}
    func evict(root: URL) async throws {}
    func currentLocality(root: URL, expectedItems: [FileProviderExpectedItem]) async throws -> ArchiveStorageLocality {
        paths = expectedItems.map { $0.url.path }
        for item in expectedItems {
            XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.path))
        }
        return .fullyLocalCurrent
    }
}
