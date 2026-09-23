import CryptoKit
import Foundation
import XCTest
@testable import NikoMusicCore

final class LocalVaultRestoreEngineTests: XCTestCase {
    func testLaunchRecoveryFailsClosedWhenRestoreStoreReconciliationThrows() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let archiveBefore = try fixture.snapshot(at: fixture.generation)
        let engine = LocalVaultRestoreEngine(activeRoot: fixture.active, archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID, resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: StepFailingRestoreStore(), projectionStore: nil,
            provider: LocalFolderArchiveStorage(root: fixture.archive),
            catalog: VaultRestoreCatalogSpy(events: VaultRestoreEventLog()),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: VaultRestoreEventLog())),
            writeAdmission: allowRestoreWrites)
        let results = await engine.recoverAtLaunch()
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(try fixture.snapshot(at: fixture.generation), archiveBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.active.appendingPathComponent("Restored").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.active.appendingPathComponent(".niko-staging").path))
    }

    func testSelectedManagedVersionSurvivesRetryOpenAndRejectsInvalidSelection() async throws {
        let fixture = try VaultRestoreFixture(projectFiles: ["Versions/Chosen.als", "Newest.cpr"])
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        try store.save(fixture.archiveRecord)
        let events = VaultRestoreEventLog()
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let engine = LocalVaultRestoreEngine(activeRoot: fixture.active, archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID, resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store, projectionStore: store, provider: LocalFolderArchiveStorage(root: fixture.archive),
            catalog: VaultRestoreCatalogSpy(events: events), projectOpener: SafeVaultProjectOpener(workspace: workspace),
            faultInjector: { point, _ in
                if point == .openingInCubase { throw VaultTransferInterruption() }
            }, writeAdmission: allowRestoreWrites)
        for path in ["../Newest.cpr", "/Newest.cpr", "Missing.cpr", "Versions/../Newest.cpr"] {
            do {
                _ = try await engine.restoreAndOpen(projectID: fixture.projectID, destinationRelativePath: "Restored", selectedProjectRelativePath: path)
                XCTFail("Expected invalid selection rejection")
            } catch { XCTAssertEqual(error as? LocalVaultRestoreError, .noSupportedProject) }
        }
        XCTAssertTrue(try store.recoverableRestoreRecords().isEmpty)
        do {
            _ = try await engine.restoreAndOpen(projectID: fixture.projectID, destinationRelativePath: "Restored", selectedProjectRelativePath: "Versions/Chosen.als")
            XCTFail("Expected interruption")
        } catch is VaultTransferInterruption {}
        let pending = try XCTUnwrap(store.recoverableRestoreRecords().first)
        let decoded = try JSONDecoder().decode(VaultRestoreRecord.self, from: JSONEncoder().encode(pending))
        XCTAssertEqual(decoded.selectedProjectRelativePath, "Versions/Chosen.als")
        XCTAssertTrue(workspace.opened.isEmpty)
        let retry = LocalVaultRestoreEngine(activeRoot: fixture.active, archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID, resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store, projectionStore: store, provider: LocalFolderArchiveStorage(root: fixture.archive),
            catalog: VaultRestoreCatalogSpy(events: events), projectOpener: SafeVaultProjectOpener(workspace: workspace),
            writeAdmission: allowRestoreWrites)
        let completed = try await retry.retryRestore(id: pending.id)
        XCTAssertNotNil(completed.completedAt)
        XCTAssertEqual(workspace.opened.map(\.lastPathComponent), ["Chosen.als"])
        try VaultManifestBuilder().verify(fixture.manifest, at: completed.destinationURL)
        try VaultManifestBuilder().verify(fixture.manifest, at: fixture.generation)
    }

    func testLinkedArchiveRecoversInterruptedCopyWithoutInventingTransfer() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let linked = fixture.archive.appendingPathComponent("Historical")
        try FileManager.default.moveItem(at: fixture.generation, to: linked)
        let location = ProjectLocation(rootID: UUID(), relativePath: "Historical", kind: .archive, availability: .local)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let validate: LocalVaultRestoreEngine.LinkedArchiveValidation = { projectID, claim, url in
            guard projectID == fixture.projectID, claim == location, url == linked else {
                throw LocalVaultRestoreError.archiveTransferBindingUnavailable
            }
        }
        let interrupted = LocalVaultRestoreEngine(activeRoot: fixture.active, archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID, resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store, provider: LocalFolderArchiveStorage(root: fixture.archive),
            catalog: VaultRestoreCatalogSpy(events: events), projectOpener: SafeVaultProjectOpener(workspace: workspace),
            faultInjector: { point, _ in
                if point == .verifyingActiveStaging { throw VaultTransferInterruption() }
            }, writeAdmission: allowRestoreWrites, linkedArchiveValidation: validate)
        do {
            _ = try await interrupted.restoreLinkedArchive(projectID: fixture.projectID, location: location,
                archiveURL: linked, manifest: fixture.manifest, destinationRelativePath: "Restored")
            XCTFail("Expected interruption")
        } catch is VaultTransferInterruption {}
        let pending = try XCTUnwrap(store.recoverableRestoreRecords().first)
        XCTAssertNil(pending.archiveTransferID)
        XCTAssertEqual(pending.linkedArchiveLocation, location)
        XCTAssertTrue(workspace.opened.isEmpty)
        let recovered = LocalVaultRestoreEngine(activeRoot: fixture.active, archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID, resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store, provider: LocalFolderArchiveStorage(root: fixture.archive),
            catalog: VaultRestoreCatalogSpy(events: events), projectOpener: SafeVaultProjectOpener(workspace: workspace),
            writeAdmission: allowRestoreWrites, linkedArchiveValidation: validate)
        let results = await recovered.recoverAtLaunch()
        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results.first?.completedAt)
        XCTAssertEqual(workspace.opened.count, 1)
        XCTAssertTrue(try store.allTransferRecords().isEmpty)
        try VaultManifestBuilder().verify(fixture.manifest, at: pending.destinationURL)
        try VaultManifestBuilder().verify(fixture.manifest, at: linked)
    }

    func testSelectedLinkedVersionSurvivesInterruptedCopyAndRecovery() async throws {
        let fixture = try VaultRestoreFixture(projectFiles: ["Versions/Chosen.als", "Newest.cpr"])
        defer { fixture.remove() }
        let linked = fixture.archive.appendingPathComponent("Historical")
        try FileManager.default.moveItem(at: fixture.generation, to: linked)
        let location = ProjectLocation(rootID: UUID(), relativePath: "Historical", kind: .archive, availability: .local)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let validate: LocalVaultRestoreEngine.LinkedArchiveValidation = { projectID, claim, url in
            guard projectID == fixture.projectID, claim == location, url == linked else {
                throw LocalVaultRestoreError.archiveTransferBindingUnavailable
            }
        }
        let interrupted = LocalVaultRestoreEngine(activeRoot: fixture.active, archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID, resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store, provider: LocalFolderArchiveStorage(root: fixture.archive),
            catalog: VaultRestoreCatalogSpy(events: events), projectOpener: SafeVaultProjectOpener(workspace: workspace),
            faultInjector: { point, _ in
                if point == .verifyingActiveStaging { throw VaultTransferInterruption() }
            }, writeAdmission: allowRestoreWrites, linkedArchiveValidation: validate)
        do {
            _ = try await interrupted.restoreLinkedArchive(projectID: fixture.projectID, location: location,
                archiveURL: linked, manifest: fixture.manifest, destinationRelativePath: "Restored", selectedProjectRelativePath: "Versions/Chosen.als")
            XCTFail("Expected interruption")
        } catch is VaultTransferInterruption {}
        let pending = try XCTUnwrap(store.recoverableRestoreRecords().first)
        XCTAssertEqual(pending.selectedProjectRelativePath, "Versions/Chosen.als")
        XCTAssertNil(pending.archiveTransferID)
        XCTAssertEqual(pending.linkedArchiveLocation, location)
        XCTAssertTrue(workspace.opened.isEmpty)
        let recovered = LocalVaultRestoreEngine(activeRoot: fixture.active, archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID, resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store, provider: LocalFolderArchiveStorage(root: fixture.archive),
            catalog: VaultRestoreCatalogSpy(events: events), projectOpener: SafeVaultProjectOpener(workspace: workspace),
            writeAdmission: allowRestoreWrites, linkedArchiveValidation: validate)
        let results = await recovered.recoverAtLaunch()
        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results.first?.completedAt)
        XCTAssertEqual(workspace.opened.map(\.lastPathComponent), ["Chosen.als"])
        XCTAssertTrue(try store.allTransferRecords().isEmpty)
        try VaultManifestBuilder().verify(fixture.manifest, at: pending.destinationURL)
        try VaultManifestBuilder().verify(fixture.manifest, at: linked)
    }

    func testLinkedArchiveRetryRejectsRevokedBindingAndChangedContent() async throws {
        for revoke in [false, true] {
            let fixture = try VaultRestoreFixture()
            defer { fixture.remove() }
            let linked = fixture.archive.appendingPathComponent("Historical")
            try FileManager.default.moveItem(at: fixture.generation, to: linked)
            let location = ProjectLocation(rootID: UUID(), relativePath: "Historical", kind: .archive, availability: .local)
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            let events = VaultRestoreEventLog()
            let workspace = VaultRestoreWorkspaceSpy(events: events)
            let initial = LocalVaultRestoreEngine(activeRoot: fixture.active, archiveRoot: fixture.archive,
                activeRootID: fixture.activeRootID, resolver: VaultRestoreResolver(record: fixture.archiveRecord),
                store: store, provider: LocalFolderArchiveStorage(root: fixture.archive),
                catalog: VaultRestoreCatalogSpy(events: events), projectOpener: SafeVaultProjectOpener(workspace: workspace),
                faultInjector: { _, _ in throw VaultTransferInterruption() },
                writeAdmission: allowRestoreWrites, linkedArchiveValidation: { _, _, _ in })
            do {
                _ = try await initial.restoreLinkedArchive(projectID: fixture.projectID, location: location,
                    archiveURL: linked, manifest: fixture.manifest, destinationRelativePath: "Restored")
                XCTFail("Expected interruption")
            } catch is VaultTransferInterruption {}
            let pending = try XCTUnwrap(store.recoverableRestoreRecords().first)
            if !revoke { try Data("changed".utf8).write(to: linked.appendingPathComponent("Synthetic Song.cpr")) }
            let retry = LocalVaultRestoreEngine(activeRoot: fixture.active, archiveRoot: fixture.archive,
                activeRootID: fixture.activeRootID, resolver: VaultRestoreResolver(record: fixture.archiveRecord),
                store: store, provider: LocalFolderArchiveStorage(root: fixture.archive),
                catalog: VaultRestoreCatalogSpy(events: events), projectOpener: SafeVaultProjectOpener(workspace: workspace),
                writeAdmission: allowRestoreWrites, linkedArchiveValidation: { _, _, _ in
                    if revoke { throw LocalVaultRestoreError.archiveTransferBindingUnavailable }
                })
            do { _ = try await retry.retryRestore(id: pending.id); XCTFail("Unsafe restore must stop") } catch {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: pending.destinationURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: pending.stagingURL.path))
            XCTAssertTrue(workspace.opened.isEmpty)
        }
    }

    func testChangedArchiveFilePersistsActionableIntegrityFailureBeforeCopying() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let provider = VaultRestoreProviderSpy(events: events, localityError: .expectedFileSizeMismatch(
            fixture.generation.appendingPathComponent("Synthetic Song.cpr"), expected: 42, actual: 43
        ))
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active, archiveRoot: fixture.archive, activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord), store: store,
            provider: provider, catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: workspace), writeAdmission: allowRestoreWrites
        )
        do {
            _ = try await engine.restoreAndOpen(projectID: fixture.projectID, destinationRelativePath: "Restored")
            XCTFail("Changed archive must not restore")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Synthetic Song.cpr changed from 42 to 43 bytes"))
        }
        let failed = try XCTUnwrap(try store.recoverableRestoreRecords().first)
        XCTAssertEqual(failed.failureReason, .archiveGenerationIntegrityMismatch)
        XCTAssertTrue(failed.error?.contains("Synthetic Song.cpr") == true)
        XCTAssertNil(failed.completedAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.destinationURL.path))
        XCTAssertEqual(provider.materializeCount, 0)
        XCTAssertTrue(workspace.opened.isEmpty)
        try VaultManifestBuilder().verify(fixture.manifest, at: fixture.generation)
    }

    func testAbletonAndMixedRestoreCopiesWholeFolderVerifiesAndOpensLiveSet() async throws {
        for files in [["Synthetic Song.als"], ["Synthetic Song.cpr", "Live/Synthetic Song.als", "Live/Backup/Old.als"]] {
            let fixture = try VaultRestoreFixture(projectFiles: files)
            defer { fixture.remove() }
            let before = try fixture.snapshot(at: fixture.generation)
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            let events = VaultRestoreEventLog()
            let workspace = VaultRestoreWorkspaceSpy(events: events)
            let engine = LocalVaultRestoreEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                activeRootID: fixture.activeRootID,
                resolver: VaultRestoreResolver(record: fixture.archiveRecord),
                store: store,
                provider: LocalFolderArchiveStorage(root: fixture.archive),
                catalog: VaultRestoreCatalogSpy(events: events),
                projectOpener: SafeVaultProjectOpener(workspace: workspace),
                writeAdmission: allowRestoreWrites
            )
            let result = try await engine.restoreAndOpen(projectID: fixture.projectID, destinationRelativePath: "Restored Song")
            XCTAssertNotNil(result.completedAt)
            XCTAssertEqual(workspace.opened.map(\.lastPathComponent), ["Synthetic Song.als"])
            XCTAssertTrue(workspace.opened.allSatisfy { $0.path.hasPrefix(result.destinationURL.path + "/") })
            XCTAssertEqual(try fixture.snapshot(at: result.destinationURL), before)
            XCTAssertEqual(try fixture.snapshot(at: fixture.generation), before)
            try VaultManifestBuilder().verify(fixture.manifest, at: result.destinationURL)
        }
    }

    func testArchiveVerifiedRestoreWithMaterializingProviderSkipsArchiveAdmissionAndMaterialize() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(
            events: events,
            supportsMaterialization: true,
            liveRequiresMaterialization: false
        )
        let admission = VaultRestoreAdmissionRecorder()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store,
            provider: provider,
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, operation in
                admission.record(request)
                if request.target == .archive {
                    throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
                }
                try await operation()
            }
        )

        let restored = try await engine.restoreAndOpen(
            projectID: fixture.projectID,
            destinationRelativePath: "Restored/Synthetic Song"
        )

        XCTAssertNotNil(restored.completedAt)
        XCTAssertEqual(admission.requests.map(\.target), [.active])
        XCTAssertEqual(provider.prepareReadCount, 1)
        XCTAssertEqual(provider.materializeCount, 0)
        XCTAssertEqual(provider.localityCheckCount, 4)
    }

    func testArchivedLocalRestoreWithMaterializingProviderSkipsArchiveAdmissionAndMaterialize() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        var archivedLocal = fixture.archiveRecord
        archivedLocal.state = .archivedLocal
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(
            events: events,
            supportsMaterialization: true,
            liveRequiresMaterialization: false
        )
        let admission = VaultRestoreAdmissionRecorder()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: archivedLocal),
            store: store,
            provider: provider,
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, operation in
                admission.record(request)
                if request.target == .archive {
                    throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
                }
                try await operation()
            }
        )

        let restored = try await engine.restoreAndOpen(
            projectID: fixture.projectID,
            destinationRelativePath: "Restored/Synthetic Song"
        )

        XCTAssertNotNil(restored.completedAt)
        XCTAssertEqual(admission.requests.map(\.target), [.active])
        XCTAssertEqual(provider.prepareReadCount, 1)
        XCTAssertEqual(provider.materializeCount, 0)
        XCTAssertEqual(provider.localityCheckCount, 4)
    }

    func testPersistedLocalRestoreRechecksLiveOnlineLocalityBeforeVerifyOrActiveCopy() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        var archivedLocal = fixture.archiveRecord
        archivedLocal.state = .archivedLocal
        try Data("changed-after-manifest".utf8).write(
            to: fixture.generation.appendingPathComponent("Synthetic Song.cpr")
        )
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(
            events: events,
            supportsMaterialization: true,
            liveRequiresMaterialization: true
        )
        let admission = VaultRestoreAdmissionRecorder()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: archivedLocal),
            store: store,
            provider: provider,
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, _ in
                admission.record(request)
                throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
            }
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected live online-only locality to require Archive admission")
        } catch {
            XCTAssertEqual(
                error as? VaultWriteAdmissionError,
                .postponed(.insufficientArchiveCapacity),
                "capacity denial must happen before manifest verification or hashing"
            )
        }

        XCTAssertEqual(provider.localityCheckCount, 1)
        XCTAssertEqual(admission.requests.map(\.target), [.archive])
        XCTAssertEqual(admission.requests.first?.targetRootURL.path, fixture.generation.path)
        XCTAssertEqual(provider.materializeCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.active.appendingPathComponent(".niko-staging").path))
    }

    func testOnlineRestoreRequiresFullyLocalAfterMaterializeBeforeManifestHash() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        var onlineOnly = fixture.archiveRecord
        onlineOnly.state = .archivedOnlineOnly
        try Data("changed-after-manifest".utf8).write(
            to: fixture.generation.appendingPathComponent("Synthetic Song.cpr")
        )
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(
            events: events,
            supportsMaterialization: true,
            liveLocalities: [.materializationRequired, .materializationRequired]
        )
        let admission = VaultRestoreAdmissionRecorder()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: onlineOnly),
            store: store,
            provider: provider,
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, operation in
                admission.record(request)
                try await operation()
            }
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected post-materialize locality to fail closed before manifest hashing")
        } catch {
            XCTAssertEqual(error as? LocalVaultRestoreError, .archiveLocalityUnavailable)
        }

        XCTAssertEqual(provider.localityCheckCount, 2)
        XCTAssertEqual(provider.materializeCount, 1)
        XCTAssertEqual(admission.requests.map(\.target), [.archive, .archive])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.active.appendingPathComponent(".niko-staging").path))
    }

    func testRestoreRejectsUnexpectedArchiveEntryBeforeAnyContentOpenOrActiveCopy() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(
            events: events,
            supportsMaterialization: false,
            liveRequiresMaterialization: false
        )
        let catalog = VaultRestoreCatalogSpy(events: events)
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let hashSpy = VaultRestoreContentHashSpy()
        let unexpected = fixture.generation.appendingPathComponent("Unexpected Online Only.wav")
        let expectedContentOpenCount = fixture.manifest.entries.filter { $0.type == .regularFile }.count
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store,
            provider: provider,
            catalog: catalog,
            projectOpener: SafeVaultProjectOpener(workspace: workspace),
            writeAdmission: { request, operation in
                if request.target == .active {
                    XCTAssertEqual(
                        hashSpy.openedURLs.count,
                        expectedContentOpenCount,
                        "the unexpected entry must be injected only after source verification"
                    )
                    try Data("online-only-placeholder".utf8).write(to: unexpected)
                }
                try await operation()
            },
            manifestBuilder: VaultManifestBuilder(contentHasher: hashSpy.hash)
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected unexpected archive entry to fail structural verification")
        } catch {
            XCTAssertEqual(error as? VaultManifestError, .mismatch)
        }

        XCTAssertEqual(provider.localityCheckCount, 4)
        XCTAssertEqual(
            hashSpy.openedURLs.count,
            expectedContentOpenCount * 2,
            "only expected source verification and retained-staging verification may open content"
        )
        XCTAssertFalse(hashSpy.openedURLs.contains(unexpected))
        let restore = try XCTUnwrap(try store.recoverableRestoreRecords().first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: restore.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: restore.stagingURL.appendingPathComponent(unexpected.lastPathComponent).path
        ))
        XCTAssertNoThrow(try VaultManifestBuilder().verify(fixture.manifest, at: restore.stagingURL))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.active.appendingPathComponent("Restored/Synthetic Song").path
        ))
        XCTAssertTrue(catalog.locations.isEmpty)
        XCTAssertTrue(workspace.opened.isEmpty)
    }

    func testOnlineRestoreRevalidatesGenerationAfterPrepareBeforeMaterialize() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let projectRoot = fixture.archive
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(fixture.projectID.description, isDirectory: true)
        let generation = projectRoot.appendingPathComponent("generation", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.generation, to: generation)
        var onlineOnly = fixture.archiveRecord
        onlineOnly.destinationURL = generation
        onlineOnly.state = .archivedOnlineOnly
        let outside = fixture.root.appendingPathComponent("outside-provider-generation", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("sentinel".utf8).write(to: outside.appendingPathComponent("sentinel.txt"))
        let outsideBefore = try fixture.snapshot(at: outside)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = BlockingVaultRestorePrepareProvider()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: onlineOnly),
            store: store,
            provider: provider,
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { _, operation in try await operation() }
        )
        let projectID = fixture.projectID
        let restore = Task {
            try await engine.restoreAndOpen(
                projectID: projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
        }
        await provider.waitUntilPrepareEntered()
        try FileManager.default.removeItem(at: projectRoot)
        try FileManager.default.createSymbolicLink(at: projectRoot, withDestinationURL: outside)
        await provider.releasePrepare()

        do {
            _ = try await restore.value
            XCTFail("expected post-prepare generation revalidation to fail closed")
        } catch {
            XCTAssertEqual(error as? LocalVaultRestoreError, .unsafeArchiveGenerationPath)
        }

        let materializeCount = await provider.currentMaterializeCount()
        XCTAssertEqual(materializeCount, 0)
        XCTAssertEqual(try fixture.snapshot(at: outside), outsideBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("generation").path))
    }

    func testOnlineRestoreMaterializationAdmissionsTargetActualGenerationVolume() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        var onlineOnly = fixture.archiveRecord
        onlineOnly.state = .archivedOnlineOnly
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let admission = VaultRestoreAdmissionRecorder()
        let events = VaultRestoreEventLog()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: onlineOnly),
            store: store,
            provider: VaultRestoreProviderSpy(events: events, supportsMaterialization: true),
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, _ in
                admission.record(request)
                throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
            }
        )

        _ = try? await engine.restoreAndOpen(
            projectID: fixture.projectID,
            destinationRelativePath: "Restored/Synthetic Song"
        )

        let request = try XCTUnwrap(admission.requests.first)
        XCTAssertEqual(request.target, .archive)
        XCTAssertEqual(request.targetRootURL.standardizedFileURL, fixture.generation.standardizedFileURL)
    }

    func testRestoreRejectsNestedProjectStagingSymlinkOutsideActive() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside-active-project-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("sentinel".utf8).write(to: outside.appendingPathComponent("sentinel.txt"))
        let before = try fixture.snapshot(at: outside)
        let projectStagingRoot = fixture.active
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(fixture.projectID.description, isDirectory: true)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store,
            provider: VaultRestoreProviderSpy(events: events, supportsMaterialization: false),
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, operation in
                if request.target == .active,
                   !FileManager.default.fileExists(atPath: projectStagingRoot.path) {
                    try FileManager.default.createDirectory(
                        at: projectStagingRoot.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try FileManager.default.createSymbolicLink(
                        at: projectStagingRoot,
                        withDestinationURL: outside
                    )
                }
                try await operation()
            }
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected nested Active staging symlink to fail closed")
        } catch {
            XCTAssertEqual(error as? LocalVaultRestoreError, .unsafeStagingPath)
        }
        XCTAssertEqual(try fixture.snapshot(at: outside), before)
    }

    func testRestoreRejectsVerifiedArchiveGenerationEscapingConfiguredGenerationsRootBeforeClaim() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let outsideRoot = fixture.root.appendingPathComponent("outside-archive-generation", isDirectory: true)
        let outsideGeneration = outsideRoot.appendingPathComponent("verified", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.generation, to: outsideGeneration)
        let generationsRoot = fixture.archive.appendingPathComponent("generations", isDirectory: true)
        let escape = generationsRoot.appendingPathComponent("escape", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outsideRoot)
        var escapedRecord = fixture.archiveRecord
        escapedRecord.destinationURL = escape.appendingPathComponent("verified", isDirectory: true)
        let before = try fixture.snapshot(at: outsideRoot)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(events: events, supportsMaterialization: false)
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: escapedRecord),
            store: store,
            provider: provider,
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { _, operation in try await operation() }
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected escaped archive generation to fail before claim/provider work")
        } catch {
            XCTAssertEqual(error as? LocalVaultRestoreError, .unsafeArchiveGenerationPath)
        }

        XCTAssertTrue(try store.recoverableRestoreRecords().isEmpty)
        XCTAssertEqual(provider.prepareReadCount, 0)
        XCTAssertEqual(provider.materializeCount, 0)
        XCTAssertEqual(try fixture.snapshot(at: outsideRoot), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.active.appendingPathComponent(".niko-staging").path))
    }

    func testRestoreBulkCopyRequiresStagingVolumeToMatchActiveCapacityTarget() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store,
            provider: VaultRestoreProviderSpy(events: events, supportsMaterialization: false),
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { _, operation in try await operation() },
            volumeIdentifier: { url in
                url.path.contains(".niko-staging") ? 2 : 1
            }
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected Active target-volume mismatch before bulk copy")
        } catch {
            XCTAssertEqual(error as? LocalVaultRestoreError, .writeTargetVolumeMismatch)
        }

        let record = try XCTUnwrap(store.recoverableRestoreRecords().first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.generation.path))
    }

    func testRestoreRejectsManagedActiveStagingRootSymlinkOutsideActive() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside-active-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("sentinel".utf8).write(to: outside.appendingPathComponent("sentinel.txt"))
        let stagingRoot = fixture.active.appendingPathComponent(".niko-staging", isDirectory: true)
        let before = try fixture.snapshot(at: outside)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store,
            provider: VaultRestoreProviderSpy(events: events),
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, operation in
                if request.target == .active,
                   !FileManager.default.fileExists(atPath: stagingRoot.path) {
                    try FileManager.default.createSymbolicLink(
                        at: stagingRoot,
                        withDestinationURL: outside
                    )
                }
                try await operation()
            }
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected managed Active staging symlink to fail closed")
        } catch {
            XCTAssertEqual(error as? LocalVaultRestoreError, .unsafeStagingPath)
        }

        XCTAssertEqual(try fixture.snapshot(at: outside), before)
    }

    func testLocalRestoreSkipsArchiveMaterializationCapacityAndOnlyChecksReadability() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(events: events, supportsMaterialization: false)
        let admission = VaultRestoreAdmissionRecorder()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store,
            provider: provider,
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, operation in
                admission.record(request)
                if request.target == .archive {
                    throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
                }
                try await operation()
            }
        )

        let restored = try await engine.restoreAndOpen(
            projectID: fixture.projectID,
            destinationRelativePath: "Restored/Synthetic Song"
        )

        XCTAssertNotNil(restored.completedAt)
        XCTAssertEqual(admission.requests.map(\.target), [.active])
        XCTAssertEqual(provider.materializeCount, 0)
        XCTAssertEqual(provider.prepareReadCount, 1)
    }

    func testOnlineRestoreMaterializationAdmissionCarriesPersistedManifest() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        var onlineOnly = fixture.archiveRecord
        onlineOnly.state = .archivedOnlineOnly
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let admission = VaultRestoreAdmissionRecorder()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: onlineOnly),
            store: store,
            provider: VaultRestoreProviderSpy(events: events, supportsMaterialization: true),
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, _ in
                admission.record(request)
                throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
            }
        )

        _ = try? await engine.restoreAndOpen(
            projectID: fixture.projectID,
            destinationRelativePath: "Restored/Synthetic Song"
        )

        let request = try XCTUnwrap(admission.requests.first)
        XCTAssertEqual(request.target, .archive)
        XCTAssertEqual(request.manifest, fixture.archiveRecord.manifest)
    }

    func testOnlineRestoreRechecksArchiveAdmissionAfterPrepareImmediatelyBeforeMaterialize() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        var onlineOnly = fixture.archiveRecord
        onlineOnly.state = .archivedOnlineOnly
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(events: events, supportsMaterialization: true)
        let admission = VaultRestoreAdmissionRecorder()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: onlineOnly),
            store: store,
            provider: provider,
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, operation in
                admission.record(request)
                if request.target == .archive, admission.requests.filter({ $0.target == .archive }).count == 2 {
                    throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
                }
                try await operation()
            }
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected the post-prepare materialization admission to deny")
        } catch {
            XCTAssertEqual(
                error as? VaultWriteAdmissionError,
                .postponed(.insufficientArchiveCapacity)
            )
        }

        XCTAssertEqual(admission.requests.map(\.target), [.archive, .archive])
        XCTAssertEqual(provider.prepareReadCount, 1)
        XCTAssertEqual(provider.materializeCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.active.appendingPathComponent(".niko-staging").path))
    }

    func testCrossVolumeRestorePromotionFailsClosedAndPreservesCompleteStaging() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let volumeLookups = RestoreVolumeLookupRecorder()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store,
            provider: VaultRestoreProviderSpy(events: events, supportsMaterialization: false),
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { _, operation in try await operation() },
            volumeIdentifier: { url in
                volumeLookups.record(url)
                if url.standardizedFileURL.path == fixture.active.standardizedFileURL.path {
                    return 1
                }
                return url.path.contains(".niko-staging") ? 1 : 2
            }
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected cross-volume Active promotion to fail closed")
        } catch {
            XCTAssertEqual(error as? LocalVaultRestoreError, .crossVolumePromotion)
        }

        let record = try XCTUnwrap(store.recoverableRestoreRecords().first)
        XCTAssertTrue(volumeLookups.urls.contains(record.stagingURL.standardizedFileURL.path))
        XCTAssertTrue(volumeLookups.urls.contains(record.destinationURL.deletingLastPathComponent().standardizedFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.destinationURL.path))
        try VaultManifestBuilder().verify(record.manifest, at: record.stagingURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.generation.path))
    }

    func testRestoreRejectsDestinationParentSymlinkInsertedAtPromotionBoundary() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside-active-destination", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("sentinel.txt")
        try Data("sentinel".utf8).write(to: sentinel)
        let destinationParent = fixture.active.appendingPathComponent("Restored", isDirectory: true)
        let injector = RestoreDestinationSymlinkInjector(
            destinationParent: destinationParent,
            outsideRoot: outside
        )
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store,
            provider: VaultRestoreProviderSpy(events: events, supportsMaterialization: false),
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { _, operation in try await operation() },
            volumeIdentifier: { url in try injector.lookup(url) }
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected the last-boundary destination symlink to fail closed")
        } catch {
            XCTAssertEqual(error as? LocalVaultRestoreError, .invalidDestination)
        }

        let record = try XCTUnwrap(store.recoverableRestoreRecords().first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("Synthetic Song").path))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("sentinel".utf8))
        try VaultManifestBuilder().verify(record.manifest, at: record.stagingURL)
    }

    func testRepeatedGetLocalAtomicallyClaimsOneIncompleteRestore() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let gate = BlockingRestoreAdmission()
        let makeEngine = {
            LocalVaultRestoreEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                activeRootID: fixture.activeRootID,
                resolver: VaultRestoreResolver(record: fixture.archiveRecord),
                store: store,
                provider: VaultRestoreProviderSpy(events: VaultRestoreEventLog()),
                catalog: VaultRestoreCatalogSpy(events: VaultRestoreEventLog()),
                projectOpener: SafeVaultProjectOpener(
                    workspace: VaultRestoreWorkspaceSpy(events: VaultRestoreEventLog())
                ),
                writeAdmission: { request, operation in
                    await gate.wait(request: request)
                    try await operation()
                }
            )
        }
        let firstEngine = makeEngine()
        let secondEngine = makeEngine()

        let first = Task {
            try? await firstEngine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
        }
        await gate.waitUntilFirstEntry()
        let second = Task {
            try? await secondEngine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
        }
        for _ in 0..<100 {
            if await gate.callCount >= 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let callsBeforeRelease = await gate.callCount
        let recordsBeforeRelease = try store.recoverableRestoreRecords()
        await gate.release()
        _ = await first.value
        _ = await second.value

        XCTAssertEqual(callsBeforeRelease, 1, "the second Get must not begin another provider/write admission")
        XCTAssertEqual(recordsBeforeRelease.count, 1)
        XCTAssertEqual(Set(recordsBeforeRelease.map(\.projectID)), [fixture.projectID])
    }

    func testRestoreMaterializationAdmissionTargetsArchiveAndDenialPreservesAllCopies() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        var onlineOnly = fixture.archiveRecord
        onlineOnly.state = .archivedOnlineOnly
        let archiveBefore = try fixture.snapshot(at: fixture.generation)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(events: events)
        let catalog = VaultRestoreCatalogSpy(events: events)
        let admission = VaultRestoreAdmissionRecorder()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: onlineOnly),
            store: store,
            provider: provider,
            catalog: catalog,
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, _ in
                admission.record(request)
                throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
            }
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected Archive-volume admission denial")
        } catch {
            XCTAssertEqual(error as? VaultWriteAdmissionError, .postponed(.insufficientArchiveCapacity))
        }

        let requests = admission.requests
        XCTAssertEqual(requests.map(\.target), [.archive])
        XCTAssertNil(requests.first?.sourceURL, "materialization must use manifest projection without enumerating an online-only generation")
        XCTAssertEqual(requests.first?.targetRootURL.path, fixture.generation.path)
        XCTAssertEqual(provider.materializeCount, 0)
        XCTAssertEqual(try fixture.snapshot(at: fixture.generation), archiveBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.active.appendingPathComponent(".niko-staging").path))
        XCTAssertTrue(catalog.locations.isEmpty)
        XCTAssertEqual(try store.recoverableRestoreRecords().first?.phase, .materializingArchive)
    }

    func testRestoreActiveCopyAdmissionTargetsActiveAndDenialCreatesNoStagingBytes() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        var onlineOnly = fixture.archiveRecord
        onlineOnly.state = .archivedOnlineOnly
        let archiveBefore = try fixture.snapshot(at: fixture.generation)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(events: events)
        let catalog = VaultRestoreCatalogSpy(events: events)
        let admission = VaultRestoreAdmissionRecorder()
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: onlineOnly),
            store: store,
            provider: provider,
            catalog: catalog,
            projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
            writeAdmission: { request, operation in
                admission.record(request)
                if request.target == .active {
                    throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
                }
                try await operation()
            }
        )

        do {
            _ = try await engine.restoreAndOpen(
                projectID: fixture.projectID,
                destinationRelativePath: "Restored/Synthetic Song"
            )
            XCTFail("expected Active-volume admission denial")
        } catch {
            XCTAssertEqual(error as? VaultWriteAdmissionError, .postponed(.insufficientArchiveCapacity))
        }

        let requests = admission.requests
        XCTAssertEqual(requests.map(\.target), [.archive, .archive, .active])
        XCTAssertEqual(requests.last?.targetRootURL.path, fixture.active.path)
        XCTAssertEqual(provider.materializeCount, 1)
        XCTAssertEqual(try fixture.snapshot(at: fixture.generation), archiveBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.active.appendingPathComponent(".niko-staging").path))
        XCTAssertTrue(catalog.locations.isEmpty)
        XCTAssertEqual(try store.recoverableRestoreRecords().first?.phase, .copyingToActiveStaging)
    }

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
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: onlineOnlyRecord),
            store: store,
            provider: VaultRestoreProviderSpy(events: events),
            catalog: VaultRestoreCatalogSpy(events: events),
            projectOpener: SafeVaultProjectOpener(workspace: workspace),
            writeAdmission: allowRestoreWrites
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
        var onlineOnly = fixture.archiveRecord
        onlineOnly.state = .archivedOnlineOnly
        let archiveBefore = try fixture.snapshot(at: fixture.generation)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(events: events)
        let catalog = VaultRestoreCatalogSpy(events: events)
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let opener = VaultRestorePersistCheckingOpener(store: store, workspace: workspace, events: events)
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: onlineOnly),
            store: store,
            provider: provider,
            catalog: catalog,
            projectOpener: opener,
            writeAdmission: allowRestoreWrites
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
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: VaultRestoreResolver(record: fixture.archiveRecord),
            store: store,
            provider: VaultRestoreProviderSpy(events: events),
            catalog: catalog,
            projectOpener: SafeVaultProjectOpener(workspace: workspace),
            writeAdmission: allowRestoreWrites
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
        XCTAssertTrue(try store.recoverableRestoreRecords().isEmpty)
    }

    func testCopyingRecoveryWithMissingStagingRewindsThroughAdmittedExactMaterialization() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        var archive = fixture.archiveRecord
        archive.state = .archivedOnlineOnly
        archive.durability = .syncedToProvider
        try store.save(archive)
        let restoreID = UUID()
        let staging = fixture.active
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(fixture.projectID.description, isDirectory: true)
            .appendingPathComponent(restoreID.uuidString.lowercased(), isDirectory: true)
        let destination = fixture.active
            .appendingPathComponent("Recovered/Provider Drift", isDirectory: true)
        let restore = VaultRestoreRecord(
            id: restoreID,
            projectID: fixture.projectID,
            archiveGenerationURL: fixture.generation,
            stagingURL: staging,
            destinationURL: destination,
            manifest: fixture.manifest,
            archiveTransferID: archive.id,
            archiveTransferState: archive.state,
            requiresArchiveMaterialization: true,
            phase: .copyingToActiveStaging
        )
        try store.saveRestore(restore)
        let archiveBefore = try fixture.snapshot(at: fixture.generation)
        let provider = ProviderDriftRecoverySpy(localities: [
            .materializationRequired,
            .materializationRequired,
            .fullyLocalCurrent,
            .fullyLocalCurrent,
            .fullyLocalCurrent,
        ])
        let admissions = VaultRestoreRecoveryAdmissionRecorder()
        let events = VaultRestoreEventLog()
        let catalog = VaultRestoreCatalogSpy(events: events)
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: store,
            store: store,
            projectionStore: store,
            provider: provider,
            catalog: catalog,
            projectOpener: SafeVaultProjectOpener(workspace: workspace),
            writeAdmission: { request, operation in
                admissions.record(
                    request,
                    persistedPhase: try store.restoreRecord(id: restoreID)?.phase
                )
                try await operation()
            }
        )

        let recovered = await engine.recoverAtLaunch()

        let result = try XCTUnwrap(recovered.first(where: { $0.id == restoreID }))
        let persisted = try XCTUnwrap(store.restoreRecord(id: restoreID))
        XCTAssertEqual(result.id, restoreID)
        XCTAssertEqual(persisted.id, restoreID)
        XCTAssertNotNil(result.completedAt)
        XCTAssertNotNil(persisted.completedAt)
        XCTAssertEqual(admissions.targets, [.archive, .archive, .active])
        XCTAssertEqual(
            admissions.persistedPhases,
            [.materializingArchive, .materializingArchive, .copyingToActiveStaging]
        )
        let materializations = await provider.materializations()
        let prepareReadCount = await provider.prepareReadCount()
        let localityCount = await provider.localityCount()
        XCTAssertEqual(materializations.count, 1)
        XCTAssertEqual(materializations.first?.location, fixture.generation)
        XCTAssertEqual(materializations.first?.manifest, fixture.manifest)
        XCTAssertEqual(prepareReadCount, 1)
        XCTAssertEqual(localityCount, 5)
        XCTAssertEqual(try fixture.snapshot(at: fixture.generation), archiveBefore)
        XCTAssertNoThrow(try VaultManifestBuilder().verify(fixture.manifest, at: destination))
        XCTAssertEqual(catalog.locations.count, 1)
        XCTAssertEqual(workspace.opened.count, 1)
    }

    func testCopyingRecoveryWithValidStagingCompletesOfflineWithoutProviderOrHydration() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        var archive = fixture.archiveRecord
        archive.state = .archivedOnlineOnly
        archive.durability = .syncedToProvider
        try store.save(archive)
        let restoreID = UUID()
        let staging = fixture.active
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(fixture.projectID.description, isDirectory: true)
            .appendingPathComponent(restoreID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(
            at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.generation, to: staging)
        let destination = fixture.active
            .appendingPathComponent("Recovered/Offline Staging", isDirectory: true)
        let restore = VaultRestoreRecord(
            id: restoreID,
            projectID: fixture.projectID,
            archiveGenerationURL: fixture.generation,
            stagingURL: staging,
            destinationURL: destination,
            manifest: fixture.manifest,
            archiveTransferID: archive.id,
            archiveTransferState: archive.state,
            requiresArchiveMaterialization: true,
            phase: .copyingToActiveStaging
        )
        try store.saveRestore(restore)
        let archiveBefore = try fixture.snapshot(at: fixture.generation)
        let provider = OfflineRestoreProviderSpy()
        let admissions = VaultRestoreAdmissionRecorder()
        let events = VaultRestoreEventLog()
        let catalog = VaultRestoreCatalogSpy(events: events)
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: store,
            store: store,
            projectionStore: store,
            provider: provider,
            catalog: catalog,
            projectOpener: SafeVaultProjectOpener(workspace: workspace),
            writeAdmission: { request, _ in
                admissions.record(request)
                throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
            }
        )

        let recovered = await engine.recoverAtLaunch()

        let result = try XCTUnwrap(recovered.first(where: { $0.id == restoreID }))
        let persisted = try XCTUnwrap(store.restoreRecord(id: restoreID))
        let providerCallCount = await provider.totalCallCount()
        XCTAssertEqual(result.id, restoreID)
        XCTAssertEqual(persisted.id, restoreID)
        XCTAssertNotNil(result.completedAt)
        XCTAssertNotNil(persisted.completedAt)
        XCTAssertEqual(providerCallCount, 0)
        XCTAssertTrue(admissions.requests.isEmpty)
        XCTAssertEqual(try fixture.snapshot(at: fixture.generation), archiveBefore)
        try VaultManifestBuilder().verify(fixture.manifest, at: destination)
        XCTAssertEqual(catalog.locations.count, 1)
        XCTAssertEqual(workspace.opened.count, 1)
    }

    func testCopyingRecoveryWithPartialStagingPreservesItAndRebuildsOnceAtFreshManagedPath() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        var archive = fixture.archiveRecord
        archive.state = .archiveVerified
        try store.save(archive)
        let restoreID = UUID()
        let staging = fixture.active
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(fixture.projectID.description, isDirectory: true)
            .appendingPathComponent(restoreID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let retainedPartial = staging.appendingPathComponent("partial-copy.bin")
        try Data("retained partial restore bytes".utf8).write(to: retainedPartial)
        let partialBefore = try fixture.snapshot(at: staging)
        let destination = fixture.active
            .appendingPathComponent("Recovered/Partial Staging", isDirectory: true)
        let restore = VaultRestoreRecord(
            id: restoreID,
            projectID: fixture.projectID,
            archiveGenerationURL: fixture.generation,
            stagingURL: staging,
            destinationURL: destination,
            manifest: fixture.manifest,
            archiveTransferID: archive.id,
            archiveTransferState: archive.state,
            requiresArchiveMaterialization: false,
            phase: .copyingToActiveStaging
        )
        try store.saveRestore(restore)
        let events = VaultRestoreEventLog()
        let provider = VaultRestoreProviderSpy(
            events: events,
            supportsMaterialization: false,
            liveRequiresMaterialization: false
        )
        let admissions = VaultRestoreAdmissionRecorder()
        let catalog = VaultRestoreCatalogSpy(events: events)
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: store,
            store: store,
            projectionStore: store,
            provider: provider,
            catalog: catalog,
            projectOpener: SafeVaultProjectOpener(workspace: workspace),
            writeAdmission: { request, operation in
                admissions.record(request)
                try await operation()
            }
        )

        let first = await engine.recoverAtLaunch()
        let afterFirst = try XCTUnwrap(store.restoreRecord(id: restoreID))
        let second = await engine.recoverAtLaunch()

        XCTAssertEqual(first.map(\.id), [restoreID])
        XCTAssertNotNil(afterFirst.completedAt)
        XCTAssertNotEqual(afterFirst.stagingURL, staging)
        XCTAssertTrue(second.isEmpty, "the preserved partial tree must not be retried on every launch")
        XCTAssertEqual(try fixture.snapshot(at: staging), partialBefore)
        let destinationVerified = (try? VaultManifestBuilder().verify(
            fixture.manifest,
            at: destination
        )) != nil
        XCTAssertTrue(destinationVerified)
        XCTAssertEqual(admissions.requests.map(\.target), [.active])
        XCTAssertEqual(provider.localityCheckCount, 1)
        XCTAssertEqual(provider.prepareReadCount, 0)
        XCTAssertEqual(provider.materializeCount, 0)
        XCTAssertEqual(catalog.locations.count, 1)
        XCTAssertEqual(workspace.opened.count, 1)
    }

    func testLegacyDuplicateRestoreRecoverySupersedesLoserBeforeExecutingNewestOwner() async throws {
        let fixture = try VaultRestoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        var archive = fixture.archiveRecord
        archive.state = .archivedOnlineOnly
        archive.durability = .syncedToProvider
        try store.save(archive)
        let olderID = UUID()
        let newerID = UUID()
        let destination = fixture.active
            .appendingPathComponent("Recovered/One Owner", isDirectory: true)
        let baseDate = Date(timeIntervalSince1970: 120_000)

        func makeRestore(id: UUID, date: Date) throws -> VaultRestoreRecord {
            let staging = fixture.active
                .appendingPathComponent(".niko-staging", isDirectory: true)
                .appendingPathComponent(fixture.projectID.description, isDirectory: true)
                .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
            try FileManager.default.createDirectory(
                at: staging.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: fixture.generation, to: staging)
            var record = VaultRestoreRecord(
                id: id,
                projectID: fixture.projectID,
                archiveGenerationURL: fixture.generation,
                stagingURL: staging,
                destinationURL: destination,
                manifest: fixture.manifest,
                archiveTransferID: archive.id,
                archiveTransferState: archive.state,
                requiresArchiveMaterialization: true,
                phase: .copyingToActiveStaging,
                createdAt: date
            )
            record.updatedAt = date
            return record
        }

        let older = try makeRestore(id: olderID, date: baseDate)
        let newer = try makeRestore(id: newerID, date: baseDate.addingTimeInterval(1))
        try store.saveRestore(older)
        try store.saveRestore(newer)
        let provider = OfflineRestoreProviderSpy()
        let admissions = VaultRestoreAdmissionRecorder()
        let executions = LegacyRestoreExecutionRecorder(
            loserID: olderID,
            expectedWinnerID: newerID
        )
        let events = VaultRestoreEventLog()
        let catalog = VaultRestoreCatalogSpy(events: events)
        let workspace = VaultRestoreWorkspaceSpy(events: events)
        let engine = LocalVaultRestoreEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            activeRootID: fixture.activeRootID,
            resolver: store,
            store: store,
            projectionStore: store,
            provider: provider,
            catalog: catalog,
            projectOpener: SafeVaultProjectOpener(workspace: workspace),
            faultInjector: { point, record in
                executions.record(
                    point: point,
                    record: record,
                    currentLoser: try store.restoreRecord(id: olderID)
                )
            },
            writeAdmission: { request, _ in
                admissions.record(request)
                throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
            }
        )

        let first = await engine.recoverAtLaunch()

        XCTAssertEqual(first.map(\.id), [newerID])
        XCTAssertNotNil(first.first?.completedAt)
        XCTAssertEqual(executions.startedIDs, [newerID])
        XCTAssertEqual(executions.firstExecutionSawRetiredLoser, true)
        let persistedLoser = try XCTUnwrap(store.restoreRecord(id: olderID))
        let loserJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(persistedLoser))
                as? [String: Any]
        )
        XCTAssertEqual(persistedLoser.phase.rawValue, "superseded")
        XCTAssertEqual(persistedLoser.supersededBy, newerID)
        XCTAssertEqual(loserJSON["supersededBy"] as? String, newerID.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: older.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newer.stagingURL.path))
        try VaultManifestBuilder().verify(fixture.manifest, at: destination)
        XCTAssertTrue(try store.recoverableRestoreRecords().isEmpty)
        let providerCallCount = await provider.totalCallCount()
        XCTAssertEqual(providerCallCount, 0)
        XCTAssertTrue(admissions.requests.isEmpty)
        XCTAssertEqual(catalog.locations.count, 1)
        XCTAssertEqual(workspace.opened.count, 1)

        let executionCountAfterFirstLaunch = executions.totalCount
        let second = await engine.recoverAtLaunch()
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(executions.totalCount, executionCountAfterFirstLaunch)

        do {
            _ = try await engine.retryRestore(id: olderID)
            XCTFail("a superseded restore loser must not be retryable")
        } catch {}
        XCTAssertEqual(executions.totalCount, executionCountAfterFirstLaunch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: older.stagingURL.path))
    }

    func testVaultRestoreEachPersistedPhaseRecoversIdempotentlyAfterInterruption() async throws {
        for faultPoint in VaultRestoreFaultPoint.allCases {
            let fixture = try VaultRestoreFixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            try store.save(fixture.archiveRecord)
            let capture = VaultRestoreRecordCapture()
            let events = VaultRestoreEventLog()
            let interruptedEngine = LocalVaultRestoreEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                activeRootID: fixture.activeRootID,
                resolver: VaultRestoreResolver(record: fixture.archiveRecord),
                store: store,
                projectionStore: store,
                provider: VaultRestoreProviderSpy(
                    events: events,
                    liveRequiresMaterialization: false
                ),
                catalog: VaultRestoreCatalogSpy(events: events),
                projectOpener: SafeVaultProjectOpener(workspace: VaultRestoreWorkspaceSpy(events: events)),
                faultInjector: { observed, record in
                    guard observed == faultPoint else { return }
                    capture.record = record
                    capture.persisted = try store.restoreRecord(id: record.id)
                    throw VaultTransferInterruption()
                },
                writeAdmission: allowRestoreWrites
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
                archiveRoot: fixture.archive,
                activeRootID: fixture.activeRootID,
                resolver: VaultRestoreResolver(record: fixture.archiveRecord),
                store: store,
                projectionStore: store,
                provider: VaultRestoreProviderSpy(
                    events: events,
                    liveRequiresMaterialization: false
                ),
                catalog: VaultRestoreCatalogSpy(events: events),
                projectOpener: SafeVaultProjectOpener(workspace: recoveryWorkspace),
                writeAdmission: allowRestoreWrites
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

    func testRecoveryRevalidatesPromotedActiveDestinationBeforeCatalogOrOpen() async throws {
        enum DestinationDrift: String {
            case contentChanged
            case entryAdded
            case entryRemoved
            case entryRenamed
            case symlinkEscape
        }

        let phases: [VaultRestorePhase] = [.persistingActiveLocation, .openingInCubase]
        let drifts: [DestinationDrift] = [
            .contentChanged,
            .entryAdded,
            .entryRemoved,
            .entryRenamed,
            .symlinkEscape,
        ]
        var violations: [String] = []

        for phase in phases {
            for drift in drifts {
                let label = "\(phase.rawValue)/\(drift.rawValue)"
                let fixture = try VaultRestoreFixture()
                defer { fixture.remove() }
                let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
                try store.save(fixture.archiveRecord)
                let interruption = VaultRestoreRecordCapture()
                let interruptedEvents = VaultRestoreEventLog()
                let faultPoint: VaultRestoreFaultPoint = phase == .persistingActiveLocation
                    ? .persistingActiveLocation
                    : .openingInCubase
                let interruptedEngine = LocalVaultRestoreEngine(
                    activeRoot: fixture.active,
                    archiveRoot: fixture.archive,
                    activeRootID: fixture.activeRootID,
                    resolver: VaultRestoreResolver(record: fixture.archiveRecord),
                    store: store,
                    projectionStore: store,
                    provider: VaultRestoreProviderSpy(
                        events: interruptedEvents,
                        liveRequiresMaterialization: false
                    ),
                    catalog: VaultRestoreCatalogSpy(events: interruptedEvents),
                    projectOpener: SafeVaultProjectOpener(
                        workspace: VaultRestoreWorkspaceSpy(events: interruptedEvents)
                    ),
                    faultInjector: { observed, record in
                        guard observed == faultPoint else { return }
                        interruption.record = record
                        throw VaultTransferInterruption()
                    },
                    writeAdmission: allowRestoreWrites
                )

                do {
                    _ = try await interruptedEngine.restoreAndOpen(
                        projectID: fixture.projectID,
                        destinationRelativePath: "Recovered/Synthetic Song"
                    )
                    XCTFail("expected post-promotion interruption for \(label)")
                } catch is VaultTransferInterruption {}

                let interrupted = try XCTUnwrap(interruption.record, label)
                let beforeDrift = try XCTUnwrap(store.restoreRecord(id: interrupted.id), label)
                XCTAssertEqual(beforeDrift.phase, phase, label)
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: beforeDrift.destinationURL.path),
                    "promotion must precede drift for \(label)"
                )

                let fileManager = FileManager.default
                let projectFile = beforeDrift.destinationURL.appendingPathComponent("Synthetic Song.cpr")
                let audioFile = beforeDrift.destinationURL.appendingPathComponent("Audio/take.wav")
                var symlinkTarget: String?
                var outsideEvidence: (url: URL, bytes: Data)?
                switch drift {
                case .contentChanged:
                    try Data("cubase-projecX".utf8).write(to: projectFile)
                case .entryAdded:
                    try Data("unexpected post-promotion entry".utf8).write(
                        to: beforeDrift.destinationURL.appendingPathComponent("unexpected.bin")
                    )
                case .entryRemoved:
                    try fileManager.removeItem(at: audioFile)
                case .entryRenamed:
                    try fileManager.moveItem(
                        at: audioFile,
                        to: audioFile.deletingLastPathComponent().appendingPathComponent("renamed.wav")
                    )
                case .symlinkEscape:
                    let outsideURL = fixture.root.appendingPathComponent("outside-active-evidence.wav")
                    let outsideBytes = Data("outside destination evidence".utf8)
                    try outsideBytes.write(to: outsideURL)
                    try fileManager.removeItem(at: audioFile)
                    try fileManager.createSymbolicLink(
                        atPath: audioFile.path,
                        withDestinationPath: outsideURL.path
                    )
                    symlinkTarget = try fileManager.destinationOfSymbolicLink(atPath: audioFile.path)
                    outsideEvidence = (outsideURL, outsideBytes)
                }

                try fileManager.createDirectory(
                    at: beforeDrift.stagingURL,
                    withIntermediateDirectories: true
                )
                try Data("retained post-promotion staging evidence".utf8).write(
                    to: beforeDrift.stagingURL.appendingPathComponent("retained-evidence.bin")
                )
                let archiveBeforeRecovery = try fixture.snapshot(at: fixture.generation)
                let destinationBeforeRecovery = try fixture.snapshot(at: beforeDrift.destinationURL)
                let stagingBeforeRecovery = try fixture.snapshot(at: beforeDrift.stagingURL)

                let recoveryEvents = VaultRestoreEventLog()
                let recoveryCatalog = VaultRestoreCatalogSpy(events: recoveryEvents)
                let recoveryWorkspace = VaultRestoreWorkspaceSpy(events: recoveryEvents)
                let recovery = LocalVaultRestoreEngine(
                    activeRoot: fixture.active,
                    archiveRoot: fixture.archive,
                    activeRootID: fixture.activeRootID,
                    resolver: VaultRestoreResolver(record: fixture.archiveRecord),
                    store: store,
                    projectionStore: store,
                    provider: VaultRestoreProviderSpy(
                        events: recoveryEvents,
                        liveRequiresMaterialization: false
                    ),
                    catalog: recoveryCatalog,
                    projectOpener: SafeVaultProjectOpener(workspace: recoveryWorkspace),
                    writeAdmission: allowRestoreWrites
                )

                let recovered = await recovery.recoverAtLaunch()
                let result = try XCTUnwrap(
                    recovered.first(where: { $0.id == interrupted.id }),
                    label
                )
                let persisted = try XCTUnwrap(store.restoreRecord(id: interrupted.id), label)
                let secondRecovery = await recovery.recoverAtLaunch()

                if result.completedAt != nil || persisted.completedAt != nil {
                    violations.append("\(label): drifted restore was marked complete")
                }
                if result.failureReason?.rawValue != "activeDestinationIntegrityMismatch"
                    || persisted.failureReason?.rawValue != "activeDestinationIntegrityMismatch" {
                    violations.append("\(label): missing typed activeDestinationIntegrityMismatch blocker")
                }
                if result.error?.isEmpty != false || persisted.error?.isEmpty != false {
                    violations.append("\(label): missing actionable persisted error")
                }
                if !recoveryCatalog.locations.isEmpty {
                    violations.append("\(label): recovery persisted a catalog location")
                }
                if !recoveryWorkspace.opened.isEmpty {
                    violations.append("\(label): recovery opened a project")
                }
                if !secondRecovery.isEmpty {
                    violations.append("\(label): typed failure replayed on the next recovery pass")
                }
                if try fixture.snapshot(at: fixture.generation) != archiveBeforeRecovery {
                    violations.append("\(label): recovery changed Archive evidence")
                }
                if try fixture.snapshot(at: beforeDrift.destinationURL) != destinationBeforeRecovery {
                    violations.append("\(label): recovery changed promoted Active evidence")
                }
                if try fixture.snapshot(at: beforeDrift.stagingURL) != stagingBeforeRecovery {
                    violations.append("\(label): recovery changed retained staging evidence")
                }
                if let symlinkTarget,
                   try fileManager.destinationOfSymbolicLink(atPath: audioFile.path) != symlinkTarget {
                    violations.append("\(label): recovery changed the escaped symlink evidence")
                }
                if let outsideEvidence,
                   try Data(contentsOf: outsideEvidence.url) != outsideEvidence.bytes {
                    violations.append("\(label): recovery changed content outside Active containment")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }
}

private let allowRestoreWrites: LocalVaultTransferEngine.WriteAdmission = { _, operation in
    try await operation()
}

private final class VaultRestoreAdmissionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [VaultWriteAdmissionRequest] = []

    var requests: [VaultWriteAdmissionRequest] { lock.withLock { storedRequests } }

    func record(_ request: VaultWriteAdmissionRequest) {
        lock.withLock { storedRequests.append(request) }
    }
}

private final class VaultRestoreRecoveryAdmissionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTargets: [VaultWriteTarget] = []
    private var storedPhases: [VaultRestorePhase?] = []

    var targets: [VaultWriteTarget] { lock.withLock { storedTargets } }
    var persistedPhases: [VaultRestorePhase?] { lock.withLock { storedPhases } }

    func record(_ request: VaultWriteAdmissionRequest, persistedPhase: VaultRestorePhase?) {
        lock.withLock {
            storedTargets.append(request.target)
            storedPhases.append(persistedPhase)
        }
    }
}

private final class LegacyRestoreExecutionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let loserID: UUID
    private let expectedWinnerID: UUID
    private var storedStartedIDs: [UUID] = []
    private var storedTotalCount = 0
    private var storedFirstExecutionSawRetiredLoser: Bool?

    init(loserID: UUID, expectedWinnerID: UUID) {
        self.loserID = loserID
        self.expectedWinnerID = expectedWinnerID
    }

    var startedIDs: [UUID] { lock.withLock { storedStartedIDs } }
    var totalCount: Int { lock.withLock { storedTotalCount } }
    var firstExecutionSawRetiredLoser: Bool? {
        lock.withLock { storedFirstExecutionSawRetiredLoser }
    }

    func record(
        point: VaultRestoreFaultPoint,
        record: VaultRestoreRecord,
        currentLoser: VaultRestoreRecord?
    ) {
        lock.withLock {
            storedTotalCount += 1
            if !storedStartedIDs.contains(record.id) {
                storedStartedIDs.append(record.id)
            }
            guard storedFirstExecutionSawRetiredLoser == nil else { return }
            let encoded = currentLoser.flatMap { try? JSONEncoder().encode($0) }
            let object = encoded.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            storedFirstExecutionSawRetiredLoser = record.id == expectedWinnerID
                && currentLoser?.id == loserID
                && currentLoser?.phase.rawValue == "superseded"
                && object?["supersededBy"] as? String == expectedWinnerID.uuidString
        }
    }
}

private final class VaultRestoreContentHashSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storedOpenedURLs: [URL] = []

    var openedURLs: [URL] { lock.withLock { storedOpenedURLs } }

    func hash(_ url: URL) throws -> (byteCount: Int64, sha256: String) {
        lock.withLock { storedOpenedURLs.append(url) }
        let data = try Data(contentsOf: url)
        return (
            Int64(data.count),
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }
}

private final class RestoreVolumeLookupRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURLs: [String] = []

    var urls: [String] { lock.withLock { storedURLs } }
    func record(_ url: URL) { lock.withLock { storedURLs.append(url.standardizedFileURL.path) } }
}

private final class RestoreDestinationSymlinkInjector: @unchecked Sendable {
    private let lock = NSLock()
    private let destinationParent: URL
    private let outsideRoot: URL
    private var injected = false

    init(destinationParent: URL, outsideRoot: URL) {
        self.destinationParent = destinationParent
        self.outsideRoot = outsideRoot
    }

    func lookup(_ url: URL) throws -> UInt64 {
        try lock.withLock {
            if !injected {
                injected = true
                try FileManager.default.createSymbolicLink(
                    at: destinationParent,
                    withDestinationURL: outsideRoot
                )
            }
            return 1
        }
    }
}

private actor BlockingRestoreAdmission {
    private var calls = 0
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    var callCount: Int { calls }

    func wait(request: VaultWriteAdmissionRequest) async {
        calls += 1
        if calls == 1 {
            let waiters = entryWaiters
            entryWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
    }

    func waitUntilFirstEntry() async {
        if calls > 0 { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private struct StepFailingRestoreStore: VaultRestoreStoring, Sendable {
    func saveRestore(_ record: VaultRestoreRecord) throws {}
    func restoreRecord(id: UUID) throws -> VaultRestoreRecord? {
        throw SQLiteArchiveDatabase.StoreError.step("injected SQLITE_CORRUPT")
    }
    func recoverableRestoreRecords() throws -> [VaultRestoreRecord] {
        throw SQLiteArchiveDatabase.StoreError.step("injected SQLITE_CORRUPT")
    }
    func reconcileRestoreRecordsForRecovery() throws -> [VaultRestoreRecord] {
        throw SQLiteArchiveDatabase.StoreError.step("injected SQLITE_CORRUPT")
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
    private var storedPrepareReadCount = 0
    private var storedLocalityCheckCount = 0
    private let supportsMaterialization: Bool
    private var liveLocalities: [ArchiveStorageLocality]
    private let localityError: FileProviderArchiveStorageError?

    init(
        events: VaultRestoreEventLog,
        supportsMaterialization: Bool = true,
        liveRequiresMaterialization: Bool? = nil,
        liveLocalities: [ArchiveStorageLocality]? = nil,
        localityError: FileProviderArchiveStorageError? = nil
    ) {
        self.events = events
        self.supportsMaterialization = supportsMaterialization
        self.localityError = localityError
        let requiresMaterialization = liveRequiresMaterialization ?? supportsMaterialization
        self.liveLocalities = liveLocalities ?? (requiresMaterialization
            ? [.materializationRequired, .fullyLocalCurrent]
            : [.fullyLocalCurrent])
    }

    var materializeCount: Int { lock.withLock { storedMaterializeCount } }
    var prepareReadCount: Int { lock.withLock { storedPrepareReadCount } }
    var localityCheckCount: Int { lock.withLock { storedLocalityCheckCount } }
    func capabilities() async throws -> StorageCapabilities { .init(waitsForDurability: false, supportsMaterialization: supportsMaterialization, supportsEviction: false) }
    func currentLocality(
        at location: URL,
        manifest: VaultManifest
    ) async throws -> ArchiveStorageLocality {
        if let localityError { throw localityError }
        return lock.withLock {
            storedLocalityCheckCount += 1
            if liveLocalities.count > 1 { return liveLocalities.removeFirst() }
            return liveLocalities.first ?? .unknown
        }
    }
    func prepareForRead(_ location: URL) async throws {
        lock.withLock { storedPrepareReadCount += 1 }
        events.append("prepare")
    }
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws {
        lock.withLock { storedMaterializeCount += 1 }
        events.append("materialize")
    }
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

private actor ProviderDriftRecoverySpy: ArchiveStorageProvider {
    struct Materialization: Equatable, Sendable {
        let location: URL
        let manifest: VaultManifest
    }

    private var localities: [ArchiveStorageLocality]
    private var storedLocalityCount = 0
    private var storedPrepareReadCount = 0
    private var storedMaterializations: [Materialization] = []

    init(localities: [ArchiveStorageLocality]) {
        self.localities = localities
    }

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: true, supportsEviction: false)
    }

    func currentLocality(
        at location: URL,
        manifest: VaultManifest
    ) async throws -> ArchiveStorageLocality {
        storedLocalityCount += 1
        if localities.count > 1 { return localities.removeFirst() }
        return localities.first ?? .fullyLocalCurrent
    }

    func prepareForRead(_ location: URL) async throws {
        storedPrepareReadCount += 1
    }

    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws {
        XCTFail("recovery must use exact manifest-bound materialization")
    }
    func materialize(_ location: URL, manifest: VaultManifest) async throws {
        storedMaterializations.append(.init(location: location, manifest: manifest))
    }
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }

    func localityCount() -> Int { storedLocalityCount }
    func prepareReadCount() -> Int { storedPrepareReadCount }
    func materializations() -> [Materialization] { storedMaterializations }
}

private actor OfflineRestoreProviderSpy: ArchiveStorageProvider {
    private var calls = 0

    func capabilities() async throws -> StorageCapabilities {
        calls += 1
        throw VaultManifestError.mismatch
    }
    func currentLocality(
        at location: URL,
        manifest: VaultManifest
    ) async throws -> ArchiveStorageLocality {
        calls += 1
        throw VaultManifestError.mismatch
    }
    func prepareForRead(_ location: URL) async throws {
        calls += 1
        throw VaultManifestError.mismatch
    }
    func prepareForWrite(at root: URL) async throws {
        calls += 1
        throw VaultManifestError.mismatch
    }
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        calls += 1
        throw VaultManifestError.mismatch
    }
    func materialize(_ location: URL) async throws {
        calls += 1
        throw VaultManifestError.mismatch
    }
    func materialize(_ location: URL, manifest: VaultManifest) async throws {
        calls += 1
        throw VaultManifestError.mismatch
    }
    func evictIfSupported(_ location: URL) async throws -> EvictionResult {
        calls += 1
        throw VaultManifestError.mismatch
    }

    func totalCallCount() -> Int { calls }
}

private actor BlockingVaultRestorePrepareProvider: ArchiveStorageProvider {
    private var prepareEntered = false
    private var prepareReleased = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var materializeCount = 0

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: true, supportsEviction: false)
    }

    func prepareForRead(_ location: URL) async throws {
        prepareEntered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if !prepareReleased {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
    }

    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws { materializeCount += 1 }
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }

    func waitUntilPrepareEntered() async {
        if prepareEntered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func releasePrepare() {
        prepareReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func currentMaterializeCount() -> Int { materializeCount }
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

    var archive: URL {
        generation.deletingLastPathComponent().deletingLastPathComponent()
    }

    init(projectFiles: [String] = ["Synthetic Song.cpr"]) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-restore-\(UUID().uuidString)", isDirectory: true)
        let active = root.appendingPathComponent("Active", isDirectory: true)
        let generation = root.appendingPathComponent("Archive/generations/verified", isDirectory: true)
        try FileManager.default.createDirectory(at: generation.appendingPathComponent("Audio", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        for (index, name) in projectFiles.enumerated() {
            let url = generation.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("synthetic-project".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index + 100))], ofItemAtPath: url.path)
        }
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
