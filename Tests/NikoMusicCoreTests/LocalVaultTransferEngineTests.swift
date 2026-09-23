import CryptoKit
import Foundation
import XCTest
@testable import NikoMusicCore

final class LocalVaultTransferEngineTests: XCTestCase {
    func testPendingUploadSurvivesRelaunchWithoutFailureBudgetAndFinishesBothBarriers() async throws {
        for pendingAtPromotion in [false, true] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            let instant = Date(timeIntervalSince1970: 50_000)
            let provider = PendingUploadProvider(pendingAtPromotion: pendingAtPromotion)
            let engine = try LocalVaultTransferEngine(
                activeRoot: fixture.active, archiveRoot: fixture.archive, store: store,
                provider: provider, now: { instant }, writeAdmission: allowVaultWrites
            )
            let original = try fixture.snapshotSource()
            var pending = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTAssertEqual(pending.state, pendingAtPromotion ? .promotingArchiveGeneration : .awaitingProviderDurability)
            XCTAssertTrue(pending.isWaitingForProviderUpload)
            XCTAssertNil(pending.error)
            XCTAssertEqual(pending.retryCount, 0)
            XCTAssertEqual(pending.nextRetryAt, instant.addingTimeInterval(60))
            let callsBefore = await provider.calls
            _ = await engine.recoverAtLaunch()
            let callsAfter = await provider.calls
            XCTAssertEqual(callsAfter, callsBefore, "No polling before the persisted deadline")
            // Reopen the journal and exceed the normal five-attempt failure budget.
            let relaunchedStore = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            for attempt in 1...6 {
                let checkTime = instant.addingTimeInterval(Double(attempt * 60))
                let resumed = try LocalVaultTransferEngine(
                    activeRoot: fixture.active, archiveRoot: fixture.archive, store: relaunchedStore,
                    provider: provider, now: { checkTime }, writeAdmission: allowVaultWrites
                )
                _ = await resumed.recoverAtLaunch()
                pending = try XCTUnwrap(relaunchedStore.record(id: pending.id))
                XCTAssertTrue(pending.isWaitingForProviderUpload)
                XCTAssertEqual(pending.retryCount, 0)
                XCTAssertNil(pending.error)
                XCTAssertEqual(try fixture.snapshotSource(), original)
            }
            await provider.finish()
            let resumed = try LocalVaultTransferEngine(
                activeRoot: fixture.active, archiveRoot: fixture.archive, store: relaunchedStore,
                provider: provider, now: { instant.addingTimeInterval(420) }, writeAdmission: allowVaultWrites
            )
            _ = await resumed.recoverAtLaunch()
            let completed = try XCTUnwrap(relaunchedStore.record(id: pending.id))
            XCTAssertEqual(completed.state, .archiveVerified)
            XCTAssertNil(completed.nextRetryAt)
            XCTAssertEqual(completed.durability, .syncedToProvider)
            try VaultManifestBuilder().verifyArchive(try XCTUnwrap(completed.manifest), at: completed.destinationURL)
            XCTAssertEqual(try fixture.snapshotSource(), original)
            XCTAssertEqual(try relaunchedStore.allTransferRecords().count, 1)
        }
    }

    func testLaunchRecoveryFailsClosedWhenTransferStoreReadsThrow() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let before = try fixture.snapshotSource()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active, archiveRoot: fixture.archive,
            store: StepFailingTransferStore(),
            writeAdmission: allowVaultWrites, removalAdmission: { _ in }
        )
        let results = await engine.recoverAtLaunch()
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(try fixture.snapshotSource(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archive.appendingPathComponent("generations").path))
    }

    func testExplicitRemovalRecoveryPreservesCompleteAndPartialActiveCopies() async throws {
        for sourceState in ["complete", "partial", "missing"] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            var record = try await verifiedArchive(fixture: fixture, store: store)
            record.state = .recoveryRequired
            record.error = .init(origin: .removingActiveCopy, reason: .unknown, message: "Interrupted")
            try store.save(record)
            if sourceState == "partial" {
                try FileManager.default.removeItem(at: fixture.source.appendingPathComponent("Audio/take.wav"))
            } else if sourceState == "missing" {
                try FileManager.default.removeItem(at: fixture.source)
            }
            let before = try fixture.snapshotSource()
            let engine = try LocalVaultTransferEngine(
                activeRoot: fixture.active, archiveRoot: fixture.archive, store: store,
                writeAdmission: allowVaultWrites, removalAdmission: { _ in }
            )
            let recovered = try await engine.recoverInterruptedRemoval(id: record.id)
            XCTAssertEqual(recovered.state, .archiveVerified)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
            if sourceState != "missing" {
                let preserved = try XCTUnwrap(recovered.preservedActiveCopies?.last)
                XCTAssertEqual(try fixture.snapshot(at: preserved), before)
            } else { XCTAssertNil(recovered.preservedActiveCopies) }
            XCTAssertEqual(try store.record(id: record.id), recovered)
            try VaultManifestBuilder().verify(try XCTUnwrap(record.manifest), at: record.destinationURL)
            do {
                _ = try await engine.recoverInterruptedRemoval(id: record.id)
                XCTFail("A completed review must not run twice")
            } catch {}
        }
    }

    func testExplicitRecoveryRejectsCorruptArchiveAndUnsafePreservationPath() async throws {
        for failure in ["corrupt", "symlink", "admission"] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            var record = try await verifiedArchive(fixture: fixture, store: store)
            record.state = .recoveryRequired
            record.error = .init(origin: .removingActiveCopy, reason: .unknown, message: "Interrupted")
            try store.save(record)
            if failure == "corrupt" {
                try Data("corrupt".utf8).write(to: record.destinationURL.appendingPathComponent("Artist Song.cpr"))
            } else if failure == "symlink" {
                try FileManager.default.createSymbolicLink(
                    at: fixture.active.appendingPathComponent(".niko-recovery"), withDestinationURL: fixture.archive
                )
            }
            let before = try fixture.snapshotSource()
            let engine = try LocalVaultTransferEngine(
                activeRoot: fixture.active, archiveRoot: fixture.archive, store: store,
                writeAdmission: allowVaultWrites,
                removalAdmission: { _ in
                    if failure == "admission" { throw VaultWriteAdmissionError.postponed(.openFiles) }
                }
            )
            do {
                _ = try await engine.recoverInterruptedRemoval(id: record.id)
                XCTFail("Unsafe recovery must fail")
            } catch {}
            XCTAssertEqual(try fixture.snapshotSource(), before)
            XCTAssertEqual(try store.record(id: record.id)?.state, .recoveryRequired)
        }
    }

    func testRecoveryDoesNotReadVerifiedArchivesWithoutOlderTransfersToRetire() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let verified = try await verifiedArchive(fixture: fixture, store: store)
        let probe = SurvivorValidationProbe()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            fileManager: SurvivorValidationFileManager(monitoredRoot: verified.destinationURL, probe: probe),
            writeAdmission: { _, _ in XCTFail("no recovery write is eligible") }
        )

        let empty = await engine.recoverAtLaunch()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(probe.totalProbeCount, 0, "a healthy library requires no archive verification")

        // This matches the legacy Chanin history: failures created after the
        // surviving archive cannot be retired by that older generation.
        var exhausted = VaultTransferRecord(
            projectID: verified.projectID,
            sourceURL: verified.sourceURL,
            stagingURL: verified.stagingURL,
            destinationURL: verified.destinationURL,
            state: .failedRecoverable,
            createdAt: verified.createdAt.addingTimeInterval(1)
        )
        exhausted.retryCount = 7
        exhausted.error = VaultTransferError(
            origin: .awaitingProviderDurability, reason: .providerUnsynced, message: "legacy failure"
        )
        try store.save(exhausted)
        let otherSong = try failedDurabilityRecord(fixture: fixture, retryCount: 7, updatedAt: Date())
        try store.save(otherSong)

        for _ in 0..<2 {
            let result = await engine.recoverAtLaunch()
            XCTAssertEqual(Set(result.map(\.id)), [exhausted.id, otherSong.id])
            XCTAssertEqual(probe.totalProbeCount, 0, "unrelated or causally older archives must not be read")
            XCTAssertEqual(try store.record(id: exhausted.id), exhausted)
            XCTAssertEqual(try store.record(id: verified.id), verified)
        }
        try VaultManifestBuilder().verify(try XCTUnwrap(verified.manifest), at: verified.destinationURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    func testArchiveRejectsNestedProjectStagingSymlinkOutsideArchive() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside-project-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("sentinel".utf8).write(to: outside.appendingPathComponent("sentinel.txt"))
        let before = try fixture.snapshot(at: outside)
        let projectID = ProjectID()
        let projectStagingRoot = fixture.archive
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: { _, operation in
                if !FileManager.default.fileExists(atPath: projectStagingRoot.path) {
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
            _ = try await engine.archive(projectID: projectID, sourceURL: fixture.source)
            XCTFail("expected nested project staging symlink to fail closed")
        } catch {
            XCTAssertEqual(error as? LocalVaultTransferError, .unsafeStagingPath)
        }
        XCTAssertEqual(try fixture.snapshot(at: outside), before)
    }

    func testArchiveRejectsNestedProjectGenerationSymlinkOutsideArchive() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside-project-generation", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("sentinel".utf8).write(to: outside.appendingPathComponent("sentinel.txt"))
        let before = try fixture.snapshot(at: outside)
        let projectID = ProjectID()
        let injector = NestedGenerationSymlinkInjector(
            projectRoot: fixture.archive
                .appendingPathComponent("generations", isDirectory: true)
                .appendingPathComponent(projectID.description, isDirectory: true),
            outsideRoot: outside
        )
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            faultInjector: { point, _ in try injector.inject(point: point) },
            writeAdmission: allowVaultWrites
        )

        do {
            _ = try await engine.archive(projectID: projectID, sourceURL: fixture.source)
            XCTFail("expected nested project generation symlink to fail closed")
        } catch {
            XCTAssertEqual(error as? LocalVaultTransferError, .unsafeDestinationPath)
        }
        XCTAssertEqual(try fixture.snapshot(at: outside), before)
    }

    func testArchiveBulkCopyRequiresStagingVolumeToMatchCapacityTarget() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: allowVaultWrites,
            volumeIdentifier: { url in
                url.path.contains(".niko-staging") ? 2 : 1
            }
        )

        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("expected target-volume mismatch before bulk copy")
        } catch {
            XCTAssertEqual(error as? LocalVaultTransferError, .writeTargetVolumeMismatch)
        }
        let record = try XCTUnwrap(store.allTransferRecords().first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    func testArchiveRejectsManagedStagingRootSymlinkOutsideArchive() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("sentinel".utf8).write(to: outside.appendingPathComponent("sentinel.txt"))
        let stagingRoot = fixture.archive.appendingPathComponent(".niko-staging", isDirectory: true)
        let before = try fixture.snapshot(at: outside)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: { _, operation in
                if !FileManager.default.fileExists(atPath: stagingRoot.path) {
                    try FileManager.default.createSymbolicLink(
                        at: stagingRoot,
                        withDestinationURL: outside
                    )
                }
                try await operation()
            }
        )

        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("expected the managed staging symlink to fail closed")
        } catch {
            XCTAssertEqual(error as? LocalVaultTransferError, .unsafeStagingPath)
        }

        XCTAssertEqual(try fixture.snapshot(at: outside), before)
    }

    func testArchiveRejectsManagedGenerationsRootSymlinkOutsideArchive() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = fixture.root.appendingPathComponent("outside-generations", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("sentinel".utf8).write(to: outside.appendingPathComponent("sentinel.txt"))
        let generationsRoot = fixture.archive.appendingPathComponent("generations", isDirectory: true)
        let before = try fixture.snapshot(at: outside)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let injector = GenerationSymlinkInjector(
            generationsRoot: generationsRoot,
            outsideRoot: outside
        )
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            faultInjector: { point, record in try injector.inject(point: point, record: record) },
            writeAdmission: allowVaultWrites
        )

        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("expected the managed generations symlink to fail closed")
        } catch {
            XCTAssertEqual(error as? LocalVaultTransferError, .unsafeDestinationPath)
        }

        XCTAssertEqual(try fixture.snapshot(at: outside), before)
    }

    func testDeniedAdmissionDoesNotRunProviderPrepareOrCreateMissingArchiveRoot() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.archive)
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let provider = RootCreatingArchiveProvider(root: fixture.archive)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: { _, _ in
                throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
            }
        )

        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("expected admission denial")
        } catch {
            XCTAssertEqual(
                error as? VaultWriteAdmissionError,
                .postponed(.insufficientArchiveCapacity)
            )
        }

        let prepareCount = await provider.prepareCount
        XCTAssertEqual(prepareCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archive.path))
    }

    func testArchiveRechecksWriteAdmissionAfterProviderPrepareBeforeBulkCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let events = ArchiveMutationEventLog()
        let provider = OrderedPrepareArchiveProvider(events: events)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: { _, operation in
                events.append("admission")
                try await operation()
            }
        )

        _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)

        XCTAssertEqual(events.values, ["admission", "prepare", "admission"])
    }

    func testCrossVolumePromotionFailsClosedAndPreservesCompleteStaging() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let admissions = VaultFaultPointRecorder()
        let volumeLookups = VolumeLookupRecorder()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: { _, operation in
                admissions.increment()
                try await operation()
            },
            volumeIdentifier: { url in
                volumeLookups.record(url)
                if url.standardizedFileURL.path == fixture.archive.standardizedFileURL.path {
                    return 1
                }
                return url.path.contains(".niko-staging") ? 1 : 2
            }
        )

        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("expected cross-volume promotion to fail closed")
        } catch {
            XCTAssertEqual(
                error as? LocalVaultTransferError,
                .crossVolumePromotion
            )
        }

        let record = try XCTUnwrap(store.allTransferRecords().first)
        XCTAssertEqual(admissions.count, 2)
        XCTAssertTrue(volumeLookups.urls.contains(record.stagingURL.standardizedFileURL.path))
        XCTAssertTrue(volumeLookups.urls.contains(record.destinationURL.deletingLastPathComponent().standardizedFileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.destinationURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    func testCompleteCopyPromotesVersionedVerifiedGenerationAndKeepsActiveBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.snapshotSource()
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: allowVaultWrites
        )

        let record = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)

        XCTAssertEqual(record.state, .archiveVerified)
        XCTAssertEqual(record.durability, .verifiedLocal)
        XCTAssertTrue(record.destinationURL.path.contains("/generations/"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.stagingURL.path))
        try VaultManifestBuilder().verify(XCTUnwrap(record.manifest), at: record.destinationURL)
        XCTAssertEqual(try fixture.snapshotSource(), original)
    }

    func testFreshArchiveSanitizesOnlyExactDSStoreFromStagingAndKeepsActiveBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("root metadata".utf8).write(to: fixture.source.appendingPathComponent(".DS_Store"))
        try Data("nested metadata".utf8).write(
            to: fixture.source.appendingPathComponent("Audio/.DS_Store")
        )
        try Data("keep exact-prefix".utf8).write(
            to: fixture.source.appendingPathComponent(".DS_Store.keep")
        )
        try Data("keep exact-suffix".utf8).write(
            to: fixture.source.appendingPathComponent("Audio/take.DS_Store")
        )
        let sourceBefore = try fixture.snapshotSource()
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: allowVaultWrites
        )

        let record = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)

        let archived = try fixture.snapshot(at: record.destinationURL)
        let manifestPaths = Set(try XCTUnwrap(record.manifest).entries.map(\.relativePath))
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        XCTAssertFalse(archived.keys.contains(".DS_Store"))
        XCTAssertFalse(archived.keys.contains("Audio/.DS_Store"))
        XCTAssertEqual(archived[".DS_Store.keep"], sourceBefore[".DS_Store.keep"])
        XCTAssertEqual(archived["Audio/take.DS_Store"], sourceBefore["Audio/take.DS_Store"])
        XCTAssertFalse(manifestPaths.contains(".DS_Store"))
        XCTAssertFalse(manifestPaths.contains("Audio/.DS_Store"))
        XCTAssertTrue(manifestPaths.contains(".DS_Store.keep"))
        XCTAssertTrue(manifestPaths.contains("Audio/take.DS_Store"))
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
            provider: provider,
            writeAdmission: allowVaultWrites
        )

        let record = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
        let barrierCount = await provider.barrierCount()
        let sawPromotedGeneration = await provider.sawPromotedGenerationAtFinalBarrier()

        XCTAssertEqual(record.state, .archiveVerified)
        XCTAssertEqual(record.durability, .syncedToProvider)
        XCTAssertEqual(barrierCount, 2)
        XCTAssertTrue(sawPromotedGeneration)
    }

    func testFinalDurabilityBarrierMutationNeverPublishesVerifiedGeneration() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let activeBefore = try fixture.snapshotSource()
        let provider = FinalDurabilityMutatingProvider()
        let removalAdmissions = VaultFaultPointRecorder()
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in removalAdmissions.increment() }
        )

        var archiveError: Error?
        do {
            let returned = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("final-barrier mutation must not return success: \(returned.state)")
        } catch {
            archiveError = error
        }

        let persisted = try XCTUnwrap(store.allTransferRecords().first)
        let generationSnapshot = try fixture.snapshot(at: persisted.destinationURL)
        let barrierCount = await provider.barrierCount()
        let evictionCount = await provider.evictionCount()

        XCTAssertEqual(archiveError as? VaultManifestError, .mismatch)
        XCTAssertEqual(persisted.state, .failedRecoverable)
        XCTAssertNotEqual(persisted.state, .archiveVerified)
        XCTAssertEqual(persisted.error?.origin, .promotingArchiveGeneration)
        XCTAssertEqual(persisted.error?.reason, .integrityMismatch)
        XCTAssertEqual(barrierCount, 2)
        XCTAssertEqual(removalAdmissions.count, 0)
        XCTAssertEqual(evictionCount, 0)
        XCTAssertEqual(try fixture.snapshotSource(), activeBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: persisted.destinationURL.path))
        let mutatedProject = generationSnapshot.first {
            $0.key == "Artist Song.cpr" || $0.key.hasSuffix("/Artist Song.cpr")
        }?.value
        let retainedAudio = generationSnapshot.first {
            $0.key == "Audio/take.wav" || $0.key.hasSuffix("/Audio/take.wav")
        }?.value
        let originalAudio = activeBefore.first {
            $0.key == "Audio/take.wav" || $0.key.hasSuffix("/Audio/take.wav")
        }?.value
        XCTAssertEqual(mutatedProject, FinalDurabilityMutatingProvider.mutatedProjectBytes)
        XCTAssertEqual(retainedAudio, originalAudio)
    }

    func testRemovalRechecksEmergencyStopAndKeepLocalAfterAwaitBeforeDeletingActive() async throws {
        var safetyFailures: [String] = []
        for policyChange in RemovalPolicyChange.allCases {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let sourceBefore = try fixture.snapshotSource()
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            let archived = try await verifiedArchive(fixture: fixture, store: store)
            let policy = RemovalPolicyRace()
            let provider = CountingRemovalProvider()
            let removalEngine = try LocalVaultTransferEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                store: store,
                provider: provider,
                writeAdmission: allowVaultWrites,
                removalAdmission: { _ in
                    try await policy.checkThenActivate(policyChange)
                }
            )

            let returned = try? await removalEngine.removeActiveCopy(after: archived)
            let persisted = try XCTUnwrap(store.record(id: archived.id))
            let evictionCount = await provider.evictionCount()
            let admissionCount = await policy.checkCount()
            let activePreserved = (try? fixture.snapshotSource()) == sourceBefore
            let archiveExists = FileManager.default.fileExists(atPath: archived.destinationURL.path)
            let archiveVerified: Bool
            do {
                try VaultManifestBuilder().verify(XCTUnwrap(archived.manifest), at: archived.destinationURL)
                archiveVerified = true
            } catch {
                archiveVerified = false
            }
            let terminalSuccess = [.archivedLocal, .archivedOnlineOnly].contains(persisted.state)
            let safetyInvariant = returned == nil
                && admissionCount >= 2
                && activePreserved
                && archiveExists
                && archiveVerified
                && !terminalSuccess
                && persisted.state == .archiveVerified
                && persisted.error?.origin == .removingActiveCopy
                && evictionCount == 0

            if !safetyInvariant {
                safetyFailures.append(
                    "\(policyChange): returnedNil=\(returned == nil), admissionCount=\(admissionCount), "
                    + "activePreserved=\(activePreserved), archiveExists=\(archiveExists), "
                    + "archiveVerified=\(archiveVerified), terminalSuccess=\(terminalSuccess), "
                    + "errorOrigin=\(String(describing: persisted.error?.origin)), evictions=\(evictionCount)"
                )
            }
            let retryEngine = try LocalVaultTransferEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                store: store,
                provider: provider,
                writeAdmission: allowVaultWrites,
                removalAdmission: { _ in }
            )
            let retried = try await retryEngine.removeActiveCopy(after: persisted)
            XCTAssertEqual(retried.id, archived.id)
            XCTAssertTrue([.archivedLocal, .archivedOnlineOnly].contains(retried.state))
            XCTAssertFalse(FileManager.default.fileExists(atPath: archived.sourceURL.path))
        }
        XCTAssertTrue(safetyFailures.isEmpty, safetyFailures.joined(separator: " | "))
    }

    func testSourceReplacedDuringRemovalAdmissionIsPreservedAsSourceMutatedRecoveryRequired() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let archived = try await verifiedArchive(fixture: fixture, store: store)
        let replacementFiles: [String: Data] = [
            "Replacement Song.cpr": Data("replacement-cubase-project".utf8),
            "Audio/replacement.wav": Data((0..<2048).map { UInt8(($0 * 3) % 251) }),
        ]
        let swapper = SamePathSourceSwapper(
            sourceURL: fixture.source,
            replacementFiles: replacementFiles
        )
        let provider = CountingRemovalProvider()
        let removalEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in
                try swapper.replaceOnce()
                await Task.yield()
            }
        )

        let returned = try? await removalEngine.removeActiveCopy(after: archived)
        let persisted = try XCTUnwrap(store.record(id: archived.id))
        let evictionCount = await provider.evictionCount()

        XCTAssertNil(returned, "a replacement tree must never become terminal removal success")
        XCTAssertEqual(persisted.state, .recoveryRequired)
        XCTAssertEqual(persisted.error?.origin, .removingActiveCopy)
        XCTAssertEqual(persisted.error?.reason, .sourceMutated)
        let retainedReplacement = try fixture.snapshotSource()
        XCTAssertEqual(retainedReplacement.count, replacementFiles.count)
        for (relativePath, expectedBytes) in replacementFiles {
            let actualBytes = retainedReplacement.first {
                $0.key == relativePath || $0.key.hasSuffix("/\(relativePath)")
            }?.value
            XCTAssertEqual(actualBytes, expectedBytes, relativePath)
        }
        XCTAssertEqual(evictionCount, 0)
        try VaultManifestBuilder().verify(XCTUnwrap(archived.manifest), at: archived.destinationURL)
    }

    func testByteIdenticalSourceReplacementDuringRemovalAdmissionIsPreservedAsSourceMutatedRecoveryRequired() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sourceBefore = try fixture.snapshotSource()
        let originalIdentity = try TestFileSystemIdentity(at: fixture.source)
        let replacementURL = fixture.root.appendingPathComponent("byte-identical-replacement", isDirectory: true)
        try FileManager.default.copyItem(at: fixture.source, to: replacementURL)
        let replacementIdentity = try TestFileSystemIdentity(at: replacementURL)
        XCTAssertNotEqual(replacementIdentity, originalIdentity, "the test requires an inode-distinct replacement")

        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let archived = try await verifiedArchive(fixture: fixture, store: store)
        try VaultManifestBuilder().verify(
            XCTUnwrap(archived.manifest),
            at: replacementURL
        )
        let swapper = PrebuiltSamePathSourceSwapper(
            sourceURL: fixture.source,
            replacementURL: replacementURL
        )
        let provider = CountingRemovalProvider()
        let removalEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in
                try swapper.replaceOnce()
                await Task.yield()
            }
        )

        var returned: VaultTransferRecord?
        var removalError: Error?
        do {
            returned = try await removalEngine.removeActiveCopy(after: archived)
        } catch {
            removalError = error
        }
        let persisted = try XCTUnwrap(store.record(id: archived.id))
        let evictionCount = await provider.evictionCount()

        XCTAssertNil(returned, "an inode-distinct replacement tree must never become removal success")
        XCTAssertEqual(removalError as? LocalVaultTransferError, .sourceMutated)
        XCTAssertEqual(persisted.state, .recoveryRequired)
        XCTAssertEqual(persisted.error?.origin, .removingActiveCopy)
        XCTAssertEqual(persisted.error?.reason, .sourceMutated)
        let sourceWasPreserved = FileManager.default.fileExists(atPath: fixture.source.path)
        XCTAssertTrue(sourceWasPreserved)
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        if sourceWasPreserved {
            XCTAssertEqual(try TestFileSystemIdentity(at: fixture.source), replacementIdentity)
            XCTAssertNotEqual(try TestFileSystemIdentity(at: fixture.source), originalIdentity)
        }
        XCTAssertEqual(evictionCount, 0)
        try VaultManifestBuilder().verify(XCTUnwrap(archived.manifest), at: archived.destinationURL)
    }

    func testCancellationDuringProviderEvictionAfterActiveRemovalStaysRecoverableAndRestorable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let archived = try await verifiedArchive(fixture: fixture, store: store)
        let provider = CancellingEvictionProvider()
        let removalEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in }
        )

        do {
            _ = try await removalEngine.removeActiveCopy(after: archived)
            XCTFail("eviction CancellationError must propagate")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        let persisted = try XCTUnwrap(store.record(id: archived.id))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.source.path),
            "Active copy was removed before provider eviction, so the boundary under test was reached"
        )
        try VaultManifestBuilder().verify(XCTUnwrap(archived.manifest), at: archived.destinationURL)
        XCTAssertEqual(persisted.error?.origin, .evictingProviderCache)
        XCTAssertEqual(
            persisted.state, .recoveryRequired,
            "cancellation after Active removal must stay recoveryRequired, not exhausted failedRecoverable"
        )
        XCTAssertLessThan(
            persisted.retryCount,
            VaultTransferRecoveryPolicy.production.maximumAutomaticAttempts,
            "cancellation after Active removal must not exhaust the automatic-attempt budget"
        )
        XCTAssertNil(persisted.nextRetryAt)
        XCTAssertEqual(persisted.manifestID, archived.manifestID)
        XCTAssertEqual(persisted.durability, archived.durability)
        let message = try XCTUnwrap(persisted.error?.message)
        XCTAssertFalse(
            message.contains("not deleted"),
            "recoveryRequired after removal must never falsely claim the source was retained: \(message)"
        )
        // The generation remains verifiable on disk while awaiting explicit review.
        try VaultManifestBuilder().verify(XCTUnwrap(persisted.manifest), at: persisted.destinationURL)
        let recoveryEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in }
        )
        let recovered = try await recoveryEngine.recoverInterruptedRemoval(id: archived.id)
        XCTAssertEqual(recovered.state, .archiveVerified)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        try VaultManifestBuilder().verify(XCTUnwrap(recovered.manifest), at: recovered.destinationURL)
        XCTAssertEqual(try store.verifiedArchiveGeneration(projectID: archived.projectID)?.id, archived.id)
    }

    func testCancellationBeforeRemovalPreservesSourceAndExhaustsAutomaticBudget() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sourceBefore = try fixture.snapshotSource()
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let cancelling = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: { _, _ in throw CancellationError() }
        )

        do {
            _ = try await cancelling.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("pre-removal CancellationError must propagate")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        let persisted = try XCTUnwrap(store.allTransferRecords().first)
        XCTAssertEqual(persisted.state, .failedRecoverable)
        XCTAssertEqual(persisted.error?.origin, .preparingArchive)
        XCTAssertEqual(persisted.retryCount, VaultTransferRecoveryPolicy.production.maximumAutomaticAttempts)
        XCTAssertNil(persisted.nextRetryAt)
        XCTAssertTrue(persisted.error?.message.contains("not deleted") ?? false)
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)

        let retryEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: allowVaultWrites
        )
        let retried = await retryEngine.retryRecoverableTransfer(id: persisted.id)
        let retriedUnwrapped = try XCTUnwrap(retried)
        XCTAssertEqual(retriedUnwrapped.state, .archiveVerified)
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        try VaultManifestBuilder().verify(XCTUnwrap(retriedUnwrapped.manifest), at: retriedUnwrapped.destinationURL)
    }

    func testCancellationDuringRemovalAdmissionKeepsVerifiedArchiveAndSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let archived = try await verifiedArchive(fixture: fixture, store: store)
        let sourceBefore = try fixture.snapshotSource()
        let cancelling = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in throw CancellationError() }
        )

        do {
            _ = try await cancelling.removeActiveCopy(after: archived)
            XCTFail("admission CancellationError must propagate")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        let persisted = try XCTUnwrap(store.record(id: archived.id))
        XCTAssertEqual(persisted.state, .archiveVerified)
        XCTAssertEqual(persisted.error?.origin, .removingActiveCopy)
        XCTAssertNil(persisted.nextRetryAt)
        XCTAssertLessThan(
            persisted.retryCount,
            VaultTransferRecoveryPolicy.production.maximumAutomaticAttempts
        )
        XCTAssertTrue(persisted.error?.message.contains("kept") ?? false)
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        try VaultManifestBuilder().verify(XCTUnwrap(archived.manifest), at: archived.destinationURL)

        let retryEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in }
        )
        let retried = try await retryEngine.removeActiveCopy(after: persisted)
        XCTAssertTrue([.archivedLocal, .archivedOnlineOnly].contains(retried.state))
        XCTAssertNil(retried.error)
        XCTAssertNil(try store.record(id: archived.id)?.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    func testCancelledEvictionRecoverySurvivesRelaunchWithoutSideEffects() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let archived = try await verifiedArchive(fixture: fixture, store: store)
        let removalEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: CancellingEvictionProvider(),
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in }
        )
        do {
            _ = try await removalEngine.removeActiveCopy(after: archived)
            XCTFail("expected eviction cancellation")
        } catch is CancellationError {}

        let cancelled = try XCTUnwrap(store.record(id: archived.id))
        XCTAssertEqual(cancelled.state, .recoveryRequired)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        // Before explicit review the store has no verified generation to restore from,
        // but the generation directory itself remains verifiable.
        XCTAssertNil(try store.verifiedArchiveGeneration(projectID: archived.projectID))
        try VaultManifestBuilder().verify(XCTUnwrap(cancelled.manifest), at: cancelled.destinationURL)

        let writeCalls = VaultFaultPointRecorder()
        let removalCalls = VaultFaultPointRecorder()
        let relaunchedStore = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let relaunched = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: relaunchedStore,
            writeAdmission: { _, _ in writeCalls.increment() },
            removalAdmission: { _ in removalCalls.increment() }
        )
        let automatic = await relaunched.recoverAtLaunch()
        XCTAssertTrue(automatic.isEmpty)
        XCTAssertEqual(writeCalls.count, 0)
        XCTAssertEqual(removalCalls.count, 0)
        XCTAssertEqual(try relaunchedStore.record(id: archived.id)?.state, .recoveryRequired)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))

        let reviewEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: relaunchedStore,
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in }
        )
        let recovered = try await reviewEngine.recoverInterruptedRemoval(id: archived.id)
        XCTAssertEqual(recovered.state, .archiveVerified)
        XCTAssertEqual(try relaunchedStore.verifiedArchiveGeneration(projectID: archived.projectID)?.id, archived.id)
        try VaultManifestBuilder().verify(XCTUnwrap(recovered.manifest), at: recovered.destinationURL)
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
            },
            writeAdmission: allowVaultWrites
        )
        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("expected interruption")
        } catch is VaultTransferInterruption {}
        let interrupted = try XCTUnwrap(capture.record)
        try FileManager.default.createDirectory(at: interrupted.destinationURL, withIntermediateDirectories: true)
        let sentinel = interrupted.destinationURL.appendingPathComponent("do-not-overwrite.txt")
        try Data("occupied".utf8).write(to: sentinel)

        let recovery = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: allowVaultWrites
        )
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
                },
                writeAdmission: allowVaultWrites
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

            let recovery = try LocalVaultTransferEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                store: store,
                writeAdmission: allowVaultWrites
            )
            let firstRecovery = await recovery.recoverAtLaunch()
            XCTAssertEqual(firstRecovery.first?.state, .archiveVerified, "recovery from \(point)")
            XCTAssertEqual(try fixture.snapshotSource(), original, "Active changed recovering \(point)")
            let verified = try XCTUnwrap(firstRecovery.first)
            try VaultManifestBuilder().verify(XCTUnwrap(verified.manifest), at: verified.destinationURL)
            let secondRecovery = await recovery.recoverAtLaunch()
            XCTAssertTrue(secondRecovery.isEmpty, "terminal record selected after \(point)")
        }
    }

    func testLaunchRecoveryResumesOnlyNewestTransferForEachProject() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let projectID = ProjectID()
        let olderID = UUID()
        let newerID = UUID()
        let olderStaging = fixture.archive
            .appendingPathComponent(".niko-staging")
            .appendingPathComponent(projectID.description)
            .appendingPathComponent(olderID.uuidString.lowercased())
        let newerStaging = fixture.archive
            .appendingPathComponent(".niko-staging")
            .appendingPathComponent(projectID.description)
            .appendingPathComponent(newerID.uuidString.lowercased())
        try FileManager.default.createDirectory(at: olderStaging, withIntermediateDirectories: true)
        try Data("obsolete staging".utf8).write(to: olderStaging.appendingPathComponent("partial.cpr"))
        try FileManager.default.copyItem(at: fixture.source, to: newerStaging)
        let newerManifest = try VaultManifestBuilder().build(at: newerStaging)

        var older = VaultTransferRecord(
            id: olderID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: olderStaging,
            destinationURL: fixture.archive.appendingPathComponent("generations/older"),
            state: .failedRecoverable,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        older.updatedAt = Date(timeIntervalSince1970: 200)
        older.error = VaultTransferError(
            origin: .copyingToArchiveStaging,
            reason: .unknown,
            message: "older failed attempt"
        )
        var newer = VaultTransferRecord(
            id: newerID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: newerStaging,
            destinationURL: fixture.archive.appendingPathComponent("generations/newer"),
            state: .awaitingProviderDurability,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        newer.updatedAt = Date(timeIntervalSince1970: 400)
        newer.manifestID = newerManifest.id
        newer.manifest = newerManifest
        newer.totalBytes = newerManifest.totalBytes
        newer.completedBytes = newerManifest.totalBytes
        try store.save(older)
        try store.save(newer)
        try FileManager.default.removeItem(at: fixture.source)

        let recovery = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: allowVaultWrites
        )
        let results = await recovery.recoverAtLaunch()

        XCTAssertEqual(results.map(\.id), [newerID])
        XCTAssertEqual(results.first?.state, .archiveVerified)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: olderStaging.path),
            "older staging remains until a later pass proves managed containment and equivalent surviving content"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertEqual(try store.record(id: olderID), older)
        XCTAssertEqual(try store.record(id: newerID)?.state, .archiveVerified)
    }

    func testLaunchRecoveryPersistsCooldownAcrossRepeatedCalls() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let now = Date(timeIntervalSince1970: 10_000)
        let record = try failedDurabilityRecord(fixture: fixture, retryCount: 1, updatedAt: now)
        try store.save(record)
        let provider = FailingDurabilityProvider()
        let recovery = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            now: { now },
            writeAdmission: allowVaultWrites
        )

        _ = await recovery.recoverAtLaunch()
        let afterFirst = try XCTUnwrap(store.record(id: record.id))
        _ = await recovery.recoverAtLaunch()
        let afterSecond = try XCTUnwrap(store.record(id: record.id))
        let barrierCount = await provider.barrierCount()

        XCTAssertEqual(barrierCount, 1)
        XCTAssertEqual(afterSecond.retryCount, afterFirst.retryCount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
    }

    func testLaunchRecoveryPersistsCooldownAcrossFreshEngineAndStore() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let now = Date(timeIntervalSince1970: 15_000)
        let record = try failedDurabilityRecord(fixture: fixture, retryCount: 1, updatedAt: now)
        try store.save(record)
        let firstProvider = FailingDurabilityProvider()
        let firstEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: firstProvider,
            now: { now },
            writeAdmission: allowVaultWrites
        )
        _ = await firstEngine.recoverAtLaunch()
        let afterFirst = try XCTUnwrap(store.record(id: record.id))

        let relaunchedStore = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let relaunchedProvider = FailingDurabilityProvider()
        let relaunchedEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: relaunchedStore,
            provider: relaunchedProvider,
            now: { now },
            writeAdmission: allowVaultWrites
        )
        _ = await relaunchedEngine.recoverAtLaunch()
        let afterRelaunch = try XCTUnwrap(relaunchedStore.record(id: record.id))
        let firstBarriers = await firstProvider.barrierCount()
        let relaunchedBarriers = await relaunchedProvider.barrierCount()

        XCTAssertEqual(firstBarriers, 1)
        XCTAssertEqual(relaunchedBarriers, 0)
        XCTAssertEqual(afterRelaunch, afterFirst)
        XCTAssertGreaterThan(try XCTUnwrap(afterRelaunch.nextRetryAt), now)
    }

    func testLaunchRecoveryStopsAfterFiveFailedAttempts() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let now = Date(timeIntervalSince1970: 20_000)
        let record = try failedDurabilityRecord(fixture: fixture, retryCount: 5, updatedAt: now)
        try store.save(record)
        let provider = FailingDurabilityProvider()
        let recovery = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            now: { now },
            writeAdmission: allowVaultWrites
        )

        _ = await recovery.recoverAtLaunch()
        let barrierCount = await provider.barrierCount()

        XCTAssertEqual(barrierCount, 0)
        XCTAssertEqual(try store.record(id: record.id), record)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
    }

    func testLaunchRecoveryMigratesLegacyDSStoreManifestBeforeRetryingExhaustedDurability() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("root metadata".utf8).write(to: fixture.source.appendingPathComponent(".DS_Store"))
        try Data("nested metadata".utf8).write(
            to: fixture.source.appendingPathComponent("Audio/.DS_Store")
        )
        try Data("keep exact-prefix".utf8).write(
            to: fixture.source.appendingPathComponent(".DS_Store.keep")
        )
        try Data("keep exact-suffix".utf8).write(
            to: fixture.source.appendingPathComponent("Audio/take.DS_Store")
        )
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let now = Date(timeIntervalSince1970: 22_000)
        var record = try failedDurabilityRecord(
            fixture: fixture,
            retryCount: 7,
            updatedAt: now.addingTimeInterval(-3 * 24 * 60 * 60)
        )
        let legacyManifest = try legacyManifestIncludingExactDSStore(at: record.stagingURL)
        record.manifestID = legacyManifest.id
        record.manifest = legacyManifest
        record.projectionSupplement = VaultProjectionSupplement(
            rootAllocatedByteCount: legacyManifest.rootAllocatedByteCount ?? 0,
            rootExtendedAttributeBytes: legacyManifest.rootExtendedAttributeBytes ?? 0,
            entries: legacyManifest.entries.map {
                .init(
                    relativePath: $0.relativePath,
                    allocatedByteCount: $0.allocatedByteCount ?? 0,
                    extendedAttributeBytes: $0.extendedAttributeBytes ?? 0
                )
            }
        )
        record.nextRetryAt = nil
        try store.save(record)
        let sourceBefore = try fixture.snapshot(at: record.sourceURL)
        let provider = PromotionDurabilityProvider(archiveRoot: fixture.archive)
        let recovery = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            now: { now },
            writeAdmission: allowVaultWrites
        )

        let results = await recovery.recoverAtLaunch()

        let recovered = try XCTUnwrap(results.first)
        let barrierCount = await provider.barrierCount()
        let generation = try fixture.snapshot(at: record.destinationURL)
        let migratedManifest = try XCTUnwrap(recovered.manifest)
        let migratedPaths = Set(migratedManifest.entries.map(\.relativePath))
        XCTAssertEqual(recovered.id, record.id)
        XCTAssertEqual(recovered.state, .archiveVerified)
        XCTAssertEqual(recovered.durability, .syncedToProvider)
        XCTAssertNotEqual(recovered.manifestID, legacyManifest.id)
        XCTAssertNil(recovered.projectionSupplement)
        XCTAssertEqual(recovered.retryCount, 0)
        XCTAssertEqual(barrierCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.destinationURL.path))
        XCTAssertEqual(try fixture.snapshot(at: record.sourceURL), sourceBefore)
        XCTAssertFalse(generation.keys.contains(".DS_Store"))
        XCTAssertFalse(generation.keys.contains("Audio/.DS_Store"))
        XCTAssertEqual(generation[".DS_Store.keep"], sourceBefore[".DS_Store.keep"])
        XCTAssertEqual(generation["Audio/take.DS_Store"], sourceBefore["Audio/take.DS_Store"])
        XCTAssertFalse(migratedPaths.contains(".DS_Store"))
        XCTAssertFalse(migratedPaths.contains("Audio/.DS_Store"))
        XCTAssertTrue(migratedManifest.entries.allSatisfy {
            $0.allocatedByteCount != nil && $0.extendedAttributeBytes != nil
        })
        try VaultManifestBuilder().verify(migratedManifest, at: recovered.destinationURL)
    }

    func testLaunchRecoveryMigratesLegacyDSStoreManifestFromCurrentDurabilityState() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("metadata".utf8).write(to: fixture.source.appendingPathComponent(".DS_Store"))
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let now = Date(timeIntervalSince1970: 22_500)
        var record = try failedDurabilityRecord(
            fixture: fixture,
            retryCount: 7,
            updatedAt: now
        )
        let legacyManifest = try legacyManifestIncludingExactDSStore(at: record.stagingURL)
        record.state = .awaitingProviderDurability
        record.error = nil
        record.manifestID = legacyManifest.id
        record.manifest = legacyManifest
        try store.save(record)
        let sourceBefore = try fixture.snapshot(at: record.sourceURL)
        let provider = PromotionDurabilityProvider(archiveRoot: fixture.archive)
        let recovery = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            now: { now },
            writeAdmission: allowVaultWrites
        )

        let results = await recovery.recoverAtLaunch()

        let recovered = try XCTUnwrap(results.first)
        let barrierCount = await provider.barrierCount()
        let generation = try fixture.snapshot(at: record.destinationURL)
        XCTAssertEqual(recovered.state, .archiveVerified)
        XCTAssertEqual(recovered.durability, .syncedToProvider)
        XCTAssertNotEqual(recovered.manifestID, legacyManifest.id)
        XCTAssertEqual(recovered.retryCount, 0)
        XCTAssertEqual(barrierCount, 2)
        XCTAssertEqual(try fixture.snapshot(at: record.sourceURL), sourceBefore)
        XCTAssertFalse(generation.keys.contains(".DS_Store"))
        try VaultManifestBuilder().verify(
            try XCTUnwrap(recovered.manifest),
            at: recovered.destinationURL
        )
    }

    func testLegacyDSStoreMigrationKeepsAllFilesWhenSubstantiveVerificationFails() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("root metadata".utf8).write(to: fixture.source.appendingPathComponent(".DS_Store"))
        try Data("nested metadata".utf8).write(
            to: fixture.source.appendingPathComponent("Audio/.DS_Store")
        )
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let now = Date(timeIntervalSince1970: 23_000)
        var record = try failedDurabilityRecord(
            fixture: fixture,
            retryCount: 7,
            updatedAt: now.addingTimeInterval(-3 * 24 * 60 * 60)
        )
        let legacyManifest = try legacyManifestIncludingExactDSStore(at: record.stagingURL)
        record.manifestID = legacyManifest.id
        record.manifest = legacyManifest
        record.nextRetryAt = nil
        try store.save(record)
        let sourceBefore = try fixture.snapshot(at: record.sourceURL)
        try Data("substantive mutation".utf8).write(
            to: record.stagingURL.appendingPathComponent("Artist Song.cpr"),
            options: .atomic
        )
        let stagingBefore = try fixture.snapshot(at: record.stagingURL)
        let provider = PromotionDurabilityProvider(archiveRoot: fixture.archive)
        let recovery = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            now: { now },
            writeAdmission: allowVaultWrites
        )

        let results = await recovery.recoverAtLaunch()

        let barrierCount = await provider.barrierCount()
        XCTAssertEqual(results, [record])
        XCTAssertEqual(try store.record(id: record.id), record)
        XCTAssertEqual(try fixture.snapshot(at: record.stagingURL), stagingBefore)
        XCTAssertEqual(try fixture.snapshot(at: record.sourceURL), sourceBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.appendingPathComponent(".DS_Store").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.appendingPathComponent("Audio/.DS_Store").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.destinationURL.path))
        XCTAssertEqual(barrierCount, 0)
    }

    func testExhaustedAutomaticRecoveryRemainsExplicitlyRetryable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let now = Date(timeIntervalSince1970: 25_000)
        let record = try failedDurabilityRecord(fixture: fixture, retryCount: 5, updatedAt: now)
        try store.save(record)
        let recovery = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            now: { now },
            writeAdmission: allowVaultWrites
        )

        let retried = await recovery.retryRecoverableTransfer(id: record.id)

        XCTAssertEqual(retried?.state, .archiveVerified)
        XCTAssertEqual(retried?.retryCount, 5)
        XCTAssertNil(retried?.nextRetryAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.stagingURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.destinationURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.sourceURL.path))
    }

    func testDestructiveFailureOriginsNeverAutoRecoverOrExposeManualRetry() async throws {
        for origin in [VaultTransferState.removingActiveCopy, .evictingProviderCache] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            let now = Date(timeIntervalSince1970: 27_000)
            var record = try failedDurabilityRecord(fixture: fixture, retryCount: 1, updatedAt: now)
            record.error = VaultTransferError(
                origin: origin,
                reason: .unknown,
                message: "destructive phase requires review"
            )
            try store.save(record)
            let provider = FailingDurabilityProvider()
            let engine = try LocalVaultTransferEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                store: store,
                provider: provider,
                now: { now },
                writeAdmission: allowVaultWrites,
                removalAdmission: { _ in XCTFail("destructive recovery must not reach removal admission") }
            )

            let automatic = await engine.recoverAtLaunch()
            // Legacy V1 failedRecoverable with a destructive origin has no retry
            // route. Launch normalizes truthfully to recoveryRequired without
            // replaying destructive work, independent of the attempt ceiling.
            XCTAssertEqual(automatic.count, 1, "automatic recovery from \(origin)")
            XCTAssertEqual(automatic.first?.state, .recoveryRequired, "automatic recovery from \(origin)")
            XCTAssertEqual(automatic.first?.error?.origin, origin, "automatic recovery from \(origin)")
            XCTAssertNil(automatic.first?.nextRetryAt, "automatic recovery from \(origin)")
            let manual = await engine.retryRecoverableTransfer(id: record.id)

            XCTAssertNil(manual, "manual Retry from \(origin)")
            let persisted = try XCTUnwrap(store.record(id: record.id))
            XCTAssertEqual(persisted.state, .recoveryRequired, "persisted migration from \(origin)")
            XCTAssertEqual(persisted.error?.origin, origin, "persisted migration from \(origin)")
            XCTAssertEqual(persisted.manifestID, record.manifestID, "generation evidence preserved for \(origin)")
            XCTAssertEqual(persisted.retryCount, record.retryCount, "generation evidence preserved for \(origin)")
            XCTAssertNil(persisted.nextRetryAt)
            let second = await engine.recoverAtLaunch()
            XCTAssertTrue(second.isEmpty, "migrated recoveryRequired is stable for \(origin)")
            let barriers = await provider.barrierCount()
            XCTAssertEqual(barriers, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: record.sourceURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
        }
    }

    func testLaunchNormalizesInterruptedDestructivePhasesToRecoveryRequiredWithoutSideEffects() async throws {
        for origin in [VaultTransferState.removingActiveCopy, .evictingProviderCache] {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            let now = Date(timeIntervalSince1970: 28_000)
            var record = try failedDurabilityRecord(
                fixture: fixture,
                retryCount: 0,
                updatedAt: now
            )
            try FileManager.default.createDirectory(
                at: record.destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: fixture.source, to: record.destinationURL)
            let manifest = try VaultManifestBuilder().build(at: record.destinationURL)
            record.state = origin
            record.error = nil
            record.manifestID = manifest.id
            record.manifest = manifest
            record.durability = .verifiedLocal
            try store.save(record)
            let sourceBefore = try fixture.snapshot(at: record.sourceURL)
            let stagingBefore = try fixture.snapshot(at: record.stagingURL)
            let generationBefore = try fixture.snapshot(at: record.destinationURL)
            let provider = OnlineSurvivorMetadataProvider(mode: .failure)
            let removalCalls = VaultFaultPointRecorder()
            let writeCalls = VaultFaultPointRecorder()
            let engine = try LocalVaultTransferEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                store: store,
                provider: provider,
                now: { now },
                writeAdmission: { _, _ in writeCalls.increment() },
                removalAdmission: { _ in removalCalls.increment() }
            )

            let first = await engine.recoverAtLaunch()
            let persisted = try XCTUnwrap(store.record(id: record.id))
            let second = await engine.recoverAtLaunch()
            let localityCalls = await provider.localityCallCount()
            let providerSideEffects = await provider.sideEffectCallCount()

            XCTAssertEqual(first.map(\.id), [record.id], "\(origin)")
            XCTAssertEqual(first.first?.state, .recoveryRequired, "\(origin)")
            XCTAssertEqual(persisted.state, .recoveryRequired, "\(origin)")
            XCTAssertEqual(persisted.error?.origin, origin, "\(origin)")
            XCTAssertTrue(second.isEmpty, "\(origin)")
            XCTAssertEqual(removalCalls.count, 0, "\(origin)")
            XCTAssertEqual(writeCalls.count, 0, "\(origin)")
            XCTAssertEqual(localityCalls, 0, "\(origin)")
            XCTAssertEqual(providerSideEffects, 0, "\(origin)")
            XCTAssertEqual(try fixture.snapshot(at: record.sourceURL), sourceBefore, "\(origin)")
            XCTAssertEqual(try fixture.snapshot(at: record.stagingURL), stagingBefore, "\(origin)")
            XCTAssertEqual(
                try fixture.snapshot(at: record.destinationURL),
                generationBefore,
                "\(origin)"
            )
        }
    }

    func testTaskCancelBeforeActiveRemovalKeepsVerifiedSourceAndRetryable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let archived = try await verifiedArchive(fixture: fixture, store: store)
        let sourceBefore = try fixture.snapshotSource()
        let gate = RemovalAdmissionGate()
        let provider = CountingRemovalProvider()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in
                await gate.signalEntryAndWaitForRelease()
            }
        )

        let task = Task {
            try await engine.removeActiveCopy(after: archived)
        }
        await gate.waitForEntry()
        // The removing phase was persisted before admission. Cancel before any
        // destructive call started; admission returns normally.
        task.cancel()
        await gate.release()

        do {
            _ = try await task.value
            XCTFail("Task.cancel before removal must propagate CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        let persisted = try XCTUnwrap(store.record(id: archived.id))
        XCTAssertEqual(persisted.state, .archiveVerified)
        XCTAssertEqual(persisted.error?.origin, .removingActiveCopy)
        XCTAssertTrue(persisted.error?.message.contains("kept") ?? false)
        XCTAssertNil(persisted.nextRetryAt)
        XCTAssertLessThan(
            persisted.retryCount,
            VaultTransferRecoveryPolicy.production.maximumAutomaticAttempts
        )
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        try VaultManifestBuilder().verify(XCTUnwrap(archived.manifest), at: archived.destinationURL)
        let evictionCount = await provider.evictionCount()
        XCTAssertEqual(evictionCount, 0)

        let retryEngine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in }
        )
        let retried = try await retryEngine.removeActiveCopy(after: persisted)
        XCTAssertTrue([.archivedLocal, .archivedOnlineOnly].contains(retried.state))
        XCTAssertNil(retried.error)
        XCTAssertNil(try store.record(id: archived.id)?.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
    }

    func testNonthrowingCancelledAdmissionIsRecheckedBeforeDeletingActive() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let archived = try await verifiedArchive(fixture: fixture, store: store)
        let sourceBefore = try fixture.snapshotSource()
        let gate = RemovalAdmissionGate()
        let provider = CountingRemovalProvider()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            writeAdmission: allowVaultWrites,
            removalAdmission: { _ in
                // Suspend, observe Task.cancel, then return normally without
                // throwing. The engine must recheck cancellation after all await
                // boundaries and before the destructive synchronous remove.
                await gate.signalEntryAndWaitForRelease()
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        )

        let task = Task {
            try await engine.removeActiveCopy(after: archived)
        }
        await gate.waitForEntry()
        task.cancel()
        await gate.release()

        do {
            _ = try await task.value
            XCTFail("cancelled nonthrowing admission must still propagate CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        let persisted = try XCTUnwrap(store.record(id: archived.id))
        XCTAssertEqual(persisted.state, .archiveVerified, "state source must stay verified when no destructive call started")
        XCTAssertEqual(persisted.error?.origin, .removingActiveCopy)
        XCTAssertTrue(persisted.error?.message.contains("kept") ?? false)
        XCTAssertEqual(try fixture.snapshotSource(), sourceBefore)
        try VaultManifestBuilder().verify(XCTUnwrap(archived.manifest), at: archived.destinationURL)
        let evictionCount = await provider.evictionCount()
        XCTAssertEqual(evictionCount, 0)
    }

    func testLaunchNormalizesLegacyFailedRecoverableDestructiveOriginsToRecoveryRequired() async throws {
        for origin in [VaultTransferState.removingActiveCopy, .evictingProviderCache] {
            for sourcePresent in [true, false] {
                let fixture = try Fixture()
                defer { fixture.remove() }
                let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
                let verified = try await verifiedArchive(fixture: fixture, store: store)
                var legacy = verified
                legacy.state = .failedRecoverable
                legacy.error = VaultTransferError(
                    origin: origin,
                    reason: .unknown,
                    message: "legacy V1 exhausted failure"
                )
                legacy.retryCount = 7
                legacy.nextRetryAt = nil
                try store.save(legacy)
                if !sourcePresent {
                    try FileManager.default.removeItem(at: fixture.source)
                }
                let sourceExistedBefore = sourcePresent
                let sourceSnapshotBefore = sourcePresent ? try fixture.snapshotSource() : nil
                let generationBefore = try fixture.snapshot(at: legacy.destinationURL)
                let manifestIDBefore = legacy.manifestID
                let durabilityBefore = legacy.durability

                let relaunchedStore = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
                let writeCalls = VaultFaultPointRecorder()
                let removalCalls = VaultFaultPointRecorder()
                let barrierProvider = FailingDurabilityProvider()
                let relaunched = try LocalVaultTransferEngine(
                    activeRoot: fixture.active,
                    archiveRoot: fixture.archive,
                    store: relaunchedStore,
                    provider: barrierProvider,
                    writeAdmission: { _, _ in writeCalls.increment() },
                    removalAdmission: { _ in removalCalls.increment() }
                )

                let automatic = await relaunched.recoverAtLaunch()
                let context = "\(origin) sourcePresent=\(sourcePresent)"

                XCTAssertEqual(automatic.count, 1, context)
                XCTAssertEqual(automatic.first?.state, .recoveryRequired, context)
                XCTAssertEqual(automatic.first?.error?.origin, origin, context)
                XCTAssertNil(automatic.first?.nextRetryAt, context)
                XCTAssertEqual(automatic.first?.manifestID, manifestIDBefore, "generation evidence preserved \(context)")
                XCTAssertEqual(automatic.first?.durability, durabilityBefore, "generation evidence preserved \(context)")
                XCTAssertEqual(automatic.first?.retryCount, 7, "generation evidence preserved \(context)")
                XCTAssertEqual(writeCalls.count, 0, "migration must not move/delete source \(context)")
                XCTAssertEqual(removalCalls.count, 0, "migration must not move/delete source \(context)")
                let barrierCount = await barrierProvider.barrierCount()
                XCTAssertEqual(barrierCount, 0, context)
                XCTAssertEqual(
                    FileManager.default.fileExists(atPath: fixture.source.path),
                    sourceExistedBefore,
                    "migration must not move/delete source \(context)"
                )
                if let expectedSource = sourceSnapshotBefore {
                    XCTAssertEqual(try fixture.snapshotSource(), expectedSource, context)
                }
                XCTAssertEqual(try fixture.snapshot(at: legacy.destinationURL), generationBefore, context)

                let persisted = try XCTUnwrap(relaunchedStore.record(id: legacy.id))
                XCTAssertEqual(persisted.state, .recoveryRequired, context)
                let second = await relaunched.recoverAtLaunch()
                XCTAssertTrue(second.isEmpty, context)

                // Subsequent explicit review/restore discovery from the migrated state.
                let reviewEngine = try LocalVaultTransferEngine(
                    activeRoot: fixture.active,
                    archiveRoot: fixture.archive,
                    store: relaunchedStore,
                    writeAdmission: allowVaultWrites,
                    removalAdmission: { _ in }
                )
                let recovered = try await reviewEngine.recoverInterruptedRemoval(id: legacy.id)
                XCTAssertEqual(recovered.state, .archiveVerified, context)
                XCTAssertEqual(try relaunchedStore.verifiedArchiveGeneration(projectID: legacy.projectID)?.id, legacy.id, context)
                try VaultManifestBuilder().verify(XCTUnwrap(recovered.manifest), at: recovered.destinationURL)
            }
        }
    }

    func testCopyingOriginRecoveryRequiresWriteAdmissionAndPreservesPartialStaging() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let now = Date(timeIntervalSince1970: 30_000)
        var record = try failedDurabilityRecord(fixture: fixture, retryCount: 1, updatedAt: now)
        record.manifestID = nil
        record.manifest = nil
        record.completedBytes = 0
        record.totalBytes = 0
        record.error = VaultTransferError(
            origin: .copyingToArchiveStaging,
            reason: .insufficientSpace,
            message: "copy requires new bytes"
        )
        try store.save(record)
        let stagingBefore = try fixture.snapshot(at: record.stagingURL)
        let admission = RecoveryAdmissionRecorder(result: false)
        let provider = FailingDurabilityProvider()
        let recovery = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            now: { now },
            writeAdmission: { request, _ in
                admission.evaluate(request)
                throw VaultWriteAdmissionError.postponed(.insufficientArchiveCapacity)
            }
        )

        _ = await recovery.recoverAtLaunch()
        let barriers = await provider.barrierCount()

        XCTAssertEqual(admission.callCount, 1)
        XCTAssertEqual(barriers, 0)
        let persisted = try XCTUnwrap(store.record(id: record.id))
        XCTAssertEqual(persisted.state, .failedRecoverable)
        XCTAssertEqual(persisted.retryCount, record.retryCount + 1)
        XCTAssertEqual(persisted.error?.reason, .insufficientSpace)
        XCTAssertGreaterThan(try XCTUnwrap(persisted.nextRetryAt), now)
        XCTAssertEqual(try fixture.snapshot(at: record.stagingURL), stagingBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.sourceURL.path))
    }

    func testCapacityPostponementStopsAfterFiveAutomaticSourceScans() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let start = Date(timeIntervalSince1970: 35_000)
        var record = try failedDurabilityRecord(fixture: fixture, retryCount: 0, updatedAt: start)
        record.manifestID = nil
        record.manifest = nil
        record.completedBytes = 0
        record.totalBytes = 0
        record.error = VaultTransferError(
            origin: .copyingToArchiveStaging,
            reason: .insufficientSpace,
            message: "capacity probe required"
        )
        try store.save(record)
        let stagingBefore = try fixture.snapshot(at: record.stagingURL)
        let clock = MutableVaultTestClock(start)
        let admission = RecoveryAdmissionRecorder(result: false)
        let copyingEntries = VaultFaultPointRecorder()
        let recovery = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            faultInjector: { point, _ in
                if point == .copyingToArchiveStaging { copyingEntries.increment() }
            },
            now: { clock.value },
            writeAdmission: { request, _ in
                admission.evaluate(request)
                throw VaultWriteAdmissionError.postponed(.invalidPolicy)
            }
        )

        for expectedAttempt in 1...5 {
            _ = await recovery.recoverAtLaunch()
            let persisted = try XCTUnwrap(store.record(id: record.id))
            XCTAssertEqual(persisted.retryCount, expectedAttempt)
            XCTAssertEqual(persisted.error?.reason, .insufficientSpace)
            clock.value = try XCTUnwrap(persisted.nextRetryAt).addingTimeInterval(1)
        }
        _ = await recovery.recoverAtLaunch()

        XCTAssertEqual(admission.callCount, 5)
        XCTAssertEqual(copyingEntries.count, 5)
        XCTAssertEqual(try store.record(id: record.id)?.retryCount, 5)
        XCTAssertEqual(try fixture.snapshot(at: record.stagingURL), stagingBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.sourceURL.path))
    }

    func testRelaunchSupersedesOlderFailedTransferWhenNewerVerifiedGenerationExists() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let oldDate = Date(timeIntervalSince1970: 40_000)
        let oldFailed = try failedDurabilityRecord(
            fixture: fixture,
            retryCount: 1,
            updatedAt: oldDate
        )
        try store.save(oldFailed)

        let survivorID = UUID()
        let survivorURL = fixture.archive
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(oldFailed.projectID.description, isDirectory: true)
            .appendingPathComponent("generation-\(survivorID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: survivorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.source, to: survivorURL)
        let survivorManifest = try VaultManifestBuilder().build(at: survivorURL)
        var survivor = VaultTransferRecord(
            id: survivorID,
            projectID: oldFailed.projectID,
            sourceURL: fixture.source,
            stagingURL: fixture.archive.appendingPathComponent(".niko-staging/survivor"),
            destinationURL: survivorURL,
            state: .archiveVerified,
            createdAt: oldDate.addingTimeInterval(10)
        )
        survivor.updatedAt = oldDate.addingTimeInterval(10)
        survivor.manifestID = survivorManifest.id
        survivor.manifest = survivorManifest
        survivor.durability = .verifiedLocal
        try store.save(survivor)
        let provider = CountingRemovalProvider()
        let writeAdmissions = VaultFaultPointRecorder()
        let relaunched = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            now: { oldDate.addingTimeInterval(20) },
            writeAdmission: { request, operation in
                writeAdmissions.increment()
                try await operation()
            }
        )

        let relaunchedResults = await relaunched.recoverAtLaunch()

        let providerCalls = await provider.barrierCount()
        let retired = try XCTUnwrap(store.record(id: oldFailed.id))
        let retiredJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(retired)) as? [String: Any]
        )
        XCTAssertGreaterThanOrEqual(
            providerCalls, 1,
            "retirement must run fresh provider reproof over the exact survivor generation"
        )
        XCTAssertEqual(retired.state.rawValue, "superseded")
        XCTAssertEqual(retiredJSON["supersededBy"] as? String, survivor.id.uuidString)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: oldFailed.stagingURL.path),
            "supersession alone must not delete staging before containment/content proof exists"
        )
        XCTAssertFalse(
            relaunchedResults.contains(where: { $0.id == oldFailed.id }),
            "a superseded older transfer must not replay a copy"
        )
        XCTAssertEqual(writeAdmissions.count, 0, "retirement must not replay bulk-copy writes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFailed.destinationURL.path))
        XCTAssertEqual(try store.verifiedArchiveGeneration(projectID: oldFailed.projectID)?.id, survivor.id)
    }

    func testLaterRetryTimestampCannotMakeOlderFailedTransferOutrankVerifiedSuccessor() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let projectID = ProjectID()
        let createdOld = Date(timeIntervalSince1970: 41_000)
        let createdNew = createdOld.addingTimeInterval(10)
        let verifiedNew = createdNew.addingTimeInterval(10)
        let retriedOld = verifiedNew.addingTimeInterval(10)

        let failedID = UUID()
        let failedStaging = fixture.archive
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent(failedID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(
            at: failedStaging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.source, to: failedStaging)
        let failedManifest = try VaultManifestBuilder().build(at: failedStaging)
        var failed = VaultTransferRecord(
            id: failedID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: failedStaging,
            destinationURL: fixture.archive
                .appendingPathComponent("generations", isDirectory: true)
                .appendingPathComponent(projectID.description, isDirectory: true)
                .appendingPathComponent("generation-\(failedID.uuidString.lowercased())", isDirectory: true),
            state: .failedRecoverable,
            createdAt: createdOld
        )
        failed.updatedAt = retriedOld
        failed.retryCount = 1
        failed.manifestID = failedManifest.id
        failed.manifest = failedManifest
        failed.completedBytes = failedManifest.totalBytes
        failed.totalBytes = failedManifest.totalBytes
        failed.error = VaultTransferError(
            origin: .awaitingProviderDurability,
            reason: .providerUnsynced,
            message: "old retry happened after the successor was already verified"
        )
        try store.save(failed)

        let survivorID = UUID()
        let survivorURL = fixture.archive
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent("generation-\(survivorID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: survivorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.source, to: survivorURL)
        let survivorManifest = try VaultManifestBuilder().build(at: survivorURL)
        var survivor = VaultTransferRecord(
            id: survivorID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: fixture.archive.appendingPathComponent(".niko-staging/survivor", isDirectory: true),
            destinationURL: survivorURL,
            state: .archiveVerified,
            createdAt: createdNew
        )
        survivor.updatedAt = verifiedNew
        survivor.manifestID = survivorManifest.id
        survivor.manifest = survivorManifest
        survivor.durability = .verifiedLocal
        try store.save(survivor)

        let provider = CountingRemovalProvider()
        let writeAdmissions = VaultFaultPointRecorder()
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            provider: provider,
            now: { retriedOld.addingTimeInterval(10) },
            writeAdmission: { request, operation in
                writeAdmissions.increment()
                try await operation()
            }
        )

        let relaunchedResults = await engine.recoverAtLaunch()

        let persistedFailed = try XCTUnwrap(store.record(id: failedID))
        let providerCalls = await provider.barrierCount()
        XCTAssertEqual(persistedFailed.state, .superseded)
        XCTAssertEqual(persistedFailed.supersededBy, survivorID)
        XCTAssertGreaterThanOrEqual(
            providerCalls, 1,
            "causal retirement must run fresh provider reproof, not trust persisted durability"
        )
        XCTAssertFalse(
            relaunchedResults.contains(where: { $0.id == failedID }),
            "a causally older retry must not outrank the verified successor"
        )
        XCTAssertEqual(writeAdmissions.count, 0, "retirement must not replay bulk-copy writes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: failedStaging.path))
        XCTAssertEqual(try store.verifiedArchiveGeneration(projectID: projectID)?.id, survivorID)
    }

    func testManyObsoleteRowsValidateEachSurvivorOnceAndNeverReadOnlineOnlyBytes() async throws {
        enum SurvivorLocality: CaseIterable { case onlineOnly, local }

        for locality in SurvivorLocality.allCases {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            let projectID = ProjectID()
            let baseDate = Date(timeIntervalSince1970: 50_000)
            var obsoleteIDs: [UUID] = []
            for index in 0..<12 {
                let id = UUID()
                obsoleteIDs.append(id)
                let staging = fixture.archive
                    .appendingPathComponent(".niko-staging", isDirectory: true)
                    .appendingPathComponent(projectID.description, isDirectory: true)
                    .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                try Data("preserved obsolete staging \(index)".utf8)
                    .write(to: staging.appendingPathComponent("partial.cpr"))
                var obsolete = VaultTransferRecord(
                    id: id,
                    projectID: projectID,
                    sourceURL: fixture.source,
                    stagingURL: staging,
                    destinationURL: fixture.archive
                        .appendingPathComponent("generations/obsolete-\(index)", isDirectory: true),
                    state: .failedRecoverable,
                    createdAt: baseDate.addingTimeInterval(Double(index))
                )
                obsolete.updatedAt = baseDate.addingTimeInterval(Double(index))
                obsolete.error = VaultTransferError(
                    origin: .removingActiveCopy,
                    reason: .unknown,
                    message: "obsolete failure must be retired without replay"
                )
                try store.save(obsolete)
            }

            let survivorID = UUID()
            let survivorURL = fixture.archive
                .appendingPathComponent("generations", isDirectory: true)
                .appendingPathComponent(projectID.description, isDirectory: true)
                .appendingPathComponent("generation-\(survivorID.uuidString.lowercased())", isDirectory: true)
            try FileManager.default.createDirectory(
                at: survivorURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: fixture.source, to: survivorURL)
            let manifest = try VaultManifestBuilder().build(at: survivorURL)
            if locality == .onlineOnly {
                let cpr = survivorURL.appendingPathComponent("Artist Song.cpr")
                try Data("provider-drift".utf8).write(to: cpr)
            }
            var survivor = VaultTransferRecord(
                id: survivorID,
                projectID: projectID,
                sourceURL: fixture.source,
                stagingURL: fixture.archive.appendingPathComponent(".niko-staging/survivor"),
                destinationURL: survivorURL,
                state: locality == .onlineOnly ? .archivedOnlineOnly : .archivedLocal,
                createdAt: baseDate.addingTimeInterval(100)
            )
            survivor.updatedAt = baseDate.addingTimeInterval(100)
            survivor.manifestID = manifest.id
            survivor.manifest = manifest
            survivor.durability = locality == .onlineOnly ? .syncedToProvider : .verifiedLocal
            try store.save(survivor)

            let validationProbe = SurvivorValidationProbe()
            let writeAdmissions = VaultFaultPointRecorder()
            let writeAdmission: LocalVaultTransferEngine.WriteAdmission = { _, operation in
                writeAdmissions.increment()
                try await operation()
            }
            if locality == .onlineOnly {
                let provider = OnlineSurvivorMetadataProvider(mode: .materializationRequired)
                let engine = try LocalVaultTransferEngine(
                    activeRoot: fixture.active,
                    archiveRoot: fixture.archive,
                    store: store,
                    provider: provider,
                    fileManager: SurvivorValidationFileManager(
                        monitoredRoot: survivorURL,
                        probe: validationProbe
                    ),
                    writeAdmission: writeAdmission
                )

                let results = await engine.recoverAtLaunch()

                let retired = try obsoleteIDs.compactMap { try store.record(id: $0) }
                XCTAssertTrue(retired.allSatisfy { $0.state == .superseded }, "\(locality)")
                XCTAssertTrue(retired.allSatisfy { $0.supersededBy == survivorID }, "\(locality)")
                XCTAssertEqual(validationProbe.totalProbeCount, 0, "online-only evidence must remain byte-neutral")
                let localityCallCount = await provider.localityCallCount()
                let sideEffectCallCount = await provider.sideEffectCallCount()
                let barrierCallCount = await provider.barrierCallCount()
                XCTAssertEqual(localityCallCount, 1, "online-only retirement requires live locality")
                XCTAssertEqual(barrierCallCount, 1, "online-only retirement requires fresh sync proof")
                XCTAssertEqual(sideEffectCallCount, 0, "online-only retirement must not materialize")
                XCTAssertEqual(writeAdmissions.count, 0, "retirement must not replay bulk-copy writes")
                XCTAssertTrue(results.allSatisfy { retired.map(\.id).contains($0.id) == false })
            } else {
                let provider = CountingRemovalProvider()
                let engine = try LocalVaultTransferEngine(
                    activeRoot: fixture.active,
                    archiveRoot: fixture.archive,
                    store: store,
                    provider: provider,
                    fileManager: SurvivorValidationFileManager(
                        monitoredRoot: survivorURL,
                        probe: validationProbe
                    ),
                    writeAdmission: writeAdmission
                )

                let results = await engine.recoverAtLaunch()

                let retired = try obsoleteIDs.compactMap { try store.record(id: $0) }
                XCTAssertTrue(retired.allSatisfy { $0.state == .superseded }, "\(locality)")
                XCTAssertTrue(retired.allSatisfy { $0.supersededBy == survivorID }, "\(locality)")
                XCTAssertEqual(validationProbe.verificationRootCount, 1, "one local survivor verify per project")
                let barrierCallCount = await provider.barrierCount()
                let evictionCallCount = await provider.evictionCount()
                XCTAssertGreaterThanOrEqual(barrierCallCount, 1, "local retirement requires fresh barrier reproof")
                XCTAssertEqual(evictionCallCount, 0)
                XCTAssertEqual(writeAdmissions.count, 0, "retirement must not replay bulk-copy writes")
                XCTAssertTrue(results.allSatisfy { retired.map(\.id).contains($0.id) == false })
            }
            XCTAssertTrue(obsoleteIDs.allSatisfy { id in
                FileManager.default.fileExists(
                    atPath: fixture.archive
                        .appendingPathComponent(".niko-staging/\(projectID.description)/\(id.uuidString.lowercased())")
                        .path
                )
            })
        }
    }

    func testOnlineOnlySurvivorRequiresBoundManifestEnvelopeAndLiveMetadataBeforeSupersession() async throws {
        enum EvidenceCase: CaseIterable {
            case valid
            case providerUnknown
            case providerError
            case wrongGenerationLeaf
            case httpsScheme
            case foreignFileHost
            case duplicatePath
            case unsafePath
            case missingRegularHash
            case invalidRegularHash
            case invalidDirectorySize
            case invalidDirectoryHash
            case missingParentDirectory
        }

        for evidenceCase in EvidenceCase.allCases {
            let fixture = try Fixture()
            defer { fixture.remove() }
            let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
            let projectID = ProjectID()
            let obsoleteID = UUID()
            let survivorID = UUID()
            let baseDate = Date(timeIntervalSince1970: 90_000)
            let obsoleteStaging = fixture.archive
                .appendingPathComponent(".niko-staging", isDirectory: true)
                .appendingPathComponent(projectID.description, isDirectory: true)
                .appendingPathComponent(obsoleteID.uuidString.lowercased(), isDirectory: true)
            try FileManager.default.createDirectory(
                at: obsoleteStaging,
                withIntermediateDirectories: true
            )
            try Data("preserve obsolete staging".utf8)
                .write(to: obsoleteStaging.appendingPathComponent("partial.cpr"))
            var obsolete = VaultTransferRecord(
                id: obsoleteID,
                projectID: projectID,
                sourceURL: fixture.source,
                stagingURL: obsoleteStaging,
                destinationURL: fixture.archive.appendingPathComponent("generations/obsolete"),
                state: .failedRecoverable,
                createdAt: baseDate
            )
            obsolete.updatedAt = baseDate
            obsolete.error = VaultTransferError(
                origin: .removingActiveCopy,
                reason: .unknown,
                message: "must never replay while survivor evidence is reviewed"
            )
            try store.save(obsolete)

            let builtManifest = try VaultManifestBuilder().build(at: fixture.source)
            let regular = try XCTUnwrap(
                builtManifest.entries.first(where: { $0.type == .regularFile })
            )
            func entry(
                path: String,
                type: VaultManifest.EntryType,
                byteCount: Int64,
                sha256: String?
            ) -> VaultManifest.Entry {
                .init(
                    relativePath: path,
                    type: type,
                    byteCount: byteCount,
                    modifiedAt: regular.modifiedAt,
                    sha256: sha256,
                    allocatedByteCount: regular.allocatedByteCount,
                    extendedAttributeBytes: regular.extendedAttributeBytes
                )
            }
            let manifest: VaultManifest
            switch evidenceCase {
            case .valid, .providerUnknown, .providerError, .wrongGenerationLeaf,
                 .httpsScheme, .foreignFileHost:
                manifest = builtManifest
            case .duplicatePath:
                manifest = VaultManifest(entries: [regular, regular])
            case .unsafePath:
                manifest = VaultManifest(entries: [entry(
                    path: "../escape.cpr",
                    type: .regularFile,
                    byteCount: regular.byteCount,
                    sha256: regular.sha256
                )])
            case .missingRegularHash:
                manifest = VaultManifest(entries: [entry(
                    path: regular.relativePath,
                    type: .regularFile,
                    byteCount: regular.byteCount,
                    sha256: nil
                )])
            case .invalidRegularHash:
                manifest = VaultManifest(entries: [entry(
                    path: regular.relativePath,
                    type: .regularFile,
                    byteCount: regular.byteCount,
                    sha256: "not-a-sha256"
                )])
            case .invalidDirectorySize:
                manifest = VaultManifest(entries: [entry(
                    path: "Folder",
                    type: .directory,
                    byteCount: 1,
                    sha256: nil
                )])
            case .invalidDirectoryHash:
                manifest = VaultManifest(entries: [entry(
                    path: "Folder",
                    type: .directory,
                    byteCount: 0,
                    sha256: String(repeating: "a", count: 64)
                )])
            case .missingParentDirectory:
                manifest = VaultManifest(entries: [entry(
                    path: "Missing Parent/\(regular.relativePath)",
                    type: .regularFile,
                    byteCount: regular.byteCount,
                    sha256: regular.sha256
                )])
            }

            let generationLeaf = evidenceCase == .wrongGenerationLeaf
                ? "unbound-generation"
                : "generation-\(survivorID.uuidString.lowercased())"
            let localSurvivorURL = fixture.archive
                .appendingPathComponent("generations", isDirectory: true)
                .appendingPathComponent(projectID.description, isDirectory: true)
                .appendingPathComponent(generationLeaf, isDirectory: true)
            let survivorURL: URL
            switch evidenceCase {
            case .httpsScheme:
                var components = URLComponents()
                components.scheme = "https"
                components.host = "archive.invalid"
                components.path = localSurvivorURL.path
                survivorURL = try XCTUnwrap(components.url)
            case .foreignFileHost:
                var components = URLComponents()
                components.scheme = "file"
                components.host = "foreignhost"
                components.path = localSurvivorURL.path
                survivorURL = try XCTUnwrap(components.url)
            default:
                survivorURL = localSurvivorURL
            }
            var survivor = VaultTransferRecord(
                id: survivorID,
                projectID: projectID,
                sourceURL: fixture.source,
                stagingURL: fixture.archive.appendingPathComponent(".niko-staging/survivor"),
                destinationURL: survivorURL,
                state: .archivedOnlineOnly,
                createdAt: baseDate.addingTimeInterval(10)
            )
            survivor.updatedAt = baseDate.addingTimeInterval(10)
            survivor.manifestID = manifest.id
            survivor.manifest = manifest
            survivor.durability = .syncedToProvider
            try store.save(survivor)

            let providerMode: OnlineSurvivorMetadataProvider.Mode
            switch evidenceCase {
            case .providerUnknown:
                providerMode = .unknown
            case .providerError:
                providerMode = .failure
            default:
                providerMode = .materializationRequired
            }
            let provider = OnlineSurvivorMetadataProvider(mode: providerMode)
            let fileProbe = SurvivorValidationProbe()
            let engine = try LocalVaultTransferEngine(
                activeRoot: fixture.active,
                archiveRoot: fixture.archive,
                store: store,
                provider: provider,
                fileManager: SurvivorValidationFileManager(
                    monitoredRoot: survivorURL,
                    probe: fileProbe
                ),
                writeAdmission: allowVaultWrites
            )

            _ = await engine.recoverAtLaunch()

            let persistedObsolete = try XCTUnwrap(store.record(id: obsoleteID))
            let shouldSupersede = evidenceCase == .valid
            XCTAssertEqual(
                persistedObsolete.state == .superseded,
                shouldSupersede,
                "\(evidenceCase)"
            )
            XCTAssertEqual(
                persistedObsolete.supersededBy,
                shouldSupersede ? survivorID : nil,
                "\(evidenceCase)"
            )
            let shouldQueryProvider = [
                EvidenceCase.valid,
                .providerUnknown,
                .providerError,
            ].contains(evidenceCase)
            let localityCallCount = await provider.localityCallCount()
            let sideEffectCallCount = await provider.sideEffectCallCount()
            let barrierCallCount = await provider.barrierCallCount()
            XCTAssertEqual(
                localityCallCount,
                shouldQueryProvider ? 1 : 0,
                "\(evidenceCase)"
            )
            XCTAssertEqual(
                barrierCallCount,
                shouldQueryProvider ? 1 : 0,
                "\(evidenceCase): retirement requires fresh sync proof without materializing"
            )
            XCTAssertEqual(sideEffectCallCount, 0, "\(evidenceCase)")
            XCTAssertEqual(fileProbe.totalProbeCount, 0, "\(evidenceCase)")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: obsoleteStaging.path),
                "\(evidenceCase)"
            )
        }
    }

    private func legacyManifestIncludingExactDSStore(at root: URL) throws -> VaultManifest {
        let observed = try VaultManifestBuilder().build(at: root)
        var entries = observed.entries.filter {
            $0.relativePath.split(separator: "/").last != ".DS_Store"
        }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else {
            throw VaultManifestError.missingRoot
        }
        while let url = enumerator.nextObject() as? URL {
            guard url.lastPathComponent == ".DS_Store" else { continue }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            let data = try Data(contentsOf: url)
            let relativePath = String(url.path.dropFirst(root.path.count + 1))
            entries.append(.init(
                relativePath: relativePath,
                type: .regularFile,
                byteCount: Int64(data.count),
                modifiedAt: values.contentModificationDate ?? .distantPast,
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            ))
        }
        return VaultManifest(
            entries: entries,
            rootAllocatedByteCount: observed.rootAllocatedByteCount,
            rootExtendedAttributeBytes: observed.rootExtendedAttributeBytes
        )
    }

    private func failedDurabilityRecord(
        fixture: Fixture,
        retryCount: Int,
        updatedAt: Date
    ) throws -> VaultTransferRecord {
        let projectID = ProjectID()
        let transferID = UUID()
        let staging = fixture.archive
            .appendingPathComponent(".niko-staging")
            .appendingPathComponent(projectID.description)
            .appendingPathComponent(transferID.uuidString.lowercased())
        try FileManager.default.createDirectory(
            at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.source, to: staging)
        let manifest = try VaultManifestBuilder().build(at: staging)
        var record = VaultTransferRecord(
            id: transferID,
            projectID: projectID,
            sourceURL: fixture.source,
            stagingURL: staging,
            destinationURL: fixture.archive
                .appendingPathComponent("generations")
                .appendingPathComponent(projectID.description)
                .appendingPathComponent("generation-\(transferID.uuidString.lowercased())"),
            state: .failedRecoverable,
            createdAt: updatedAt
        )
        record.updatedAt = updatedAt
        record.retryCount = retryCount
        record.manifestID = manifest.id
        record.manifest = manifest
        record.completedBytes = manifest.totalBytes
        record.totalBytes = manifest.totalBytes
        record.error = VaultTransferError(
            origin: .awaitingProviderDurability,
            reason: .providerUnsynced,
            message: "durabilityUnavailable"
        )
        return record
    }

    private func verifiedArchive(
        fixture: Fixture,
        store: SQLiteVaultTransferStore
    ) async throws -> VaultTransferRecord {
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: allowVaultWrites
        )
        return try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
    }
}

private let allowVaultWrites: LocalVaultTransferEngine.WriteAdmission = { _, operation in
    try await operation()
}

private enum RemovalPolicyChange: String, CaseIterable, Sendable {
    case emergencyStop
    case keepLocal
}

private enum RemovalPolicyTestError: Error {
    case blocked(RemovalPolicyChange)
}

private actor RemovalPolicyRace {
    private var isBlocked = false
    private var checks = 0

    func checkThenActivate(_ change: RemovalPolicyChange) async throws {
        checks += 1
        if isBlocked {
            throw RemovalPolicyTestError.blocked(change)
        }
        await Task.yield()
        isBlocked = true
    }

    func checkCount() -> Int { checks }
}

private actor RemovalAdmissionGate {
    private var hasEntered = false
    private var isReleased = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func signalEntryAndWaitForRelease() async {
        hasEntered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        if isReleased { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitForEntry() async {
        if hasEntered { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor CountingRemovalProvider: ArchiveStorageProvider {
    private var evictions = 0
    private var barriers = 0

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: false, supportsEviction: false)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        barriers += 1
        return .verifiedLocal
    }
    func materialize(_ location: URL) async throws {}

    func evictIfSupported(_ location: URL) async throws -> EvictionResult {
        evictions += 1
        return .unsupported
    }

    func evictionCount() -> Int { evictions }
    func barrierCount() -> Int { barriers }
}

private actor CancellingEvictionProvider: ArchiveStorageProvider {
    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: false, supportsEviction: true)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws {}

    func evictIfSupported(_ location: URL) async throws -> EvictionResult {
        throw CancellationError()
    }
}

private final class SamePathSourceSwapper: @unchecked Sendable {
    private let lock = NSLock()
    private let sourceURL: URL
    private let replacementFiles: [String: Data]
    private var didReplace = false

    init(sourceURL: URL, replacementFiles: [String: Data]) {
        self.sourceURL = sourceURL
        self.replacementFiles = replacementFiles
    }

    func replaceOnce() throws {
        try lock.withLock {
            guard !didReplace else { return }
            didReplace = true
            try FileManager.default.removeItem(at: sourceURL)
            try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
            for (relativePath, data) in replacementFiles {
                let destination = sourceURL.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: destination)
            }
        }
    }
}

private final class PrebuiltSamePathSourceSwapper: @unchecked Sendable {
    private let lock = NSLock()
    private let sourceURL: URL
    private let replacementURL: URL
    private var didReplace = false

    init(sourceURL: URL, replacementURL: URL) {
        self.sourceURL = sourceURL
        self.replacementURL = replacementURL
    }

    func replaceOnce() throws {
        try lock.withLock {
            guard !didReplace else { return }
            didReplace = true
            try FileManager.default.removeItem(at: sourceURL)
            try FileManager.default.moveItem(at: replacementURL, to: sourceURL)
        }
    }
}

private struct TestFileSystemIdentity: Equatable {
    let device: UInt64
    let inode: UInt64

    init(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        self.device = device.uint64Value
        self.inode = inode.uint64Value
    }
}

private actor RootCreatingArchiveProvider: ArchiveStorageProvider {
    private let root: URL
    private(set) var prepareCount = 0

    init(root: URL) { self.root = root }

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: false, supportsEviction: false)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {
        prepareCount += 1
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

private final class ArchiveMutationEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] { lock.withLock { storedValues } }
    func append(_ value: String) { lock.withLock { storedValues.append(value) } }
}

private struct OrderedPrepareArchiveProvider: ArchiveStorageProvider {
    let events: ArchiveMutationEventLog

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: false, supportsEviction: false)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws { events.append("prepare") }
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

private final class GenerationSymlinkInjector: @unchecked Sendable {
    private let generationsRoot: URL
    private let outsideRoot: URL

    init(generationsRoot: URL, outsideRoot: URL) {
        self.generationsRoot = generationsRoot
        self.outsideRoot = outsideRoot
    }

    func inject(point: VaultTransferFaultPoint, record: VaultTransferRecord) throws {
        guard point == .promotingArchiveGeneration else { return }
        if FileManager.default.fileExists(atPath: generationsRoot.path) {
            try FileManager.default.removeItem(at: generationsRoot)
        }
        try FileManager.default.createDirectory(
            at: outsideRoot.appendingPathComponent(record.projectID.description, isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: generationsRoot,
            withDestinationURL: outsideRoot
        )
    }
}

private final class NestedGenerationSymlinkInjector: @unchecked Sendable {
    private let projectRoot: URL
    private let outsideRoot: URL

    init(projectRoot: URL, outsideRoot: URL) {
        self.projectRoot = projectRoot
        self.outsideRoot = outsideRoot
    }

    func inject(point: VaultTransferFaultPoint) throws {
        guard point == .promotingArchiveGeneration else { return }
        try FileManager.default.createDirectory(
            at: projectRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: projectRoot,
            withDestinationURL: outsideRoot
        )
    }
}

private actor FailingDurabilityProvider: ArchiveStorageProvider {
    private var barriers = 0

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: true, supportsMaterialization: true, supportsEviction: true)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}

    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        barriers += 1
        throw FileProviderArchiveStorageError.durabilityUnavailable
    }

    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
    func barrierCount() -> Int { barriers }
}

private actor OnlineSurvivorMetadataProvider: ArchiveStorageProvider {
    enum Mode: Sendable {
        case materializationRequired
        case unknown
        case failure
    }

    private let mode: Mode
    private var localityCalls = 0
    private var sideEffectCalls = 0
    private var barrierCalls = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func capabilities() async throws -> StorageCapabilities {
        .init(
            waitsForDurability: true,
            supportsMaterialization: true,
            supportsEviction: true
        )
    }

    func currentLocality(
        at location: URL,
        manifest: VaultManifest
    ) async throws -> ArchiveStorageLocality {
        localityCalls += 1
        switch mode {
        case .materializationRequired:
            return .materializationRequired
        case .unknown:
            return .unknown
        case .failure:
            throw VaultManifestError.mismatch
        }
    }

    func prepareForRead(_ location: URL) async throws {
        sideEffectCalls += 1
    }

    func prepareForWrite(at root: URL) async throws {
        sideEffectCalls += 1
    }

    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        barrierCalls += 1
        return .syncedToProvider
    }

    func materialize(_ location: URL) async throws {
        sideEffectCalls += 1
    }

    func materialize(_ location: URL, manifest: VaultManifest) async throws {
        sideEffectCalls += 1
    }

    func evictIfSupported(_ location: URL) async throws -> EvictionResult {
        sideEffectCalls += 1
        return .unsupported
    }

    func localityCallCount() -> Int { localityCalls }
    func sideEffectCallCount() -> Int { sideEffectCalls }
    func barrierCallCount() -> Int { barrierCalls }
}

private final class RecoveryAdmissionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    init(result _: Bool) {}

    var callCount: Int { lock.withLock { calls } }

    func evaluate(_ request: VaultWriteAdmissionRequest) {
        lock.withLock { calls += 1 }
    }
}

private final class MutableVaultTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) { storedValue = value }

    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private final class VaultFaultPointRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int { lock.withLock { storedCount } }
    func increment() { lock.withLock { storedCount += 1 } }
}

private final class VolumeLookupRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURLs: [String] = []

    var urls: [String] { lock.withLock { storedURLs } }
    func record(_ url: URL) { lock.withLock { storedURLs.append(url.standardizedFileURL.path) } }
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

private actor FinalDurabilityMutatingProvider: ArchiveStorageProvider {
    static let mutatedProjectBytes = Data("mutated-during-final-durability".utf8)

    private var barriers = 0
    private var evictions = 0

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: true, supportsMaterialization: true, supportsEviction: true)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}

    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        barriers += 1
        if barriers == 2 {
            try Self.mutatedProjectBytes.write(
                to: location.appendingPathComponent("Artist Song.cpr"),
                options: .atomic
            )
        }
        return .syncedToProvider
    }

    func materialize(_ location: URL) async throws {}

    func evictIfSupported(_ location: URL) async throws -> EvictionResult {
        evictions += 1
        return .evicted
    }

    func barrierCount() -> Int { barriers }
    func evictionCount() -> Int { evictions }
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

private final class SurvivorValidationFileManager: FileManager {
    private let monitoredRoot: String
    private let probe: SurvivorValidationProbe

    init(monitoredRoot: URL, probe: SurvivorValidationProbe) {
        self.monitoredRoot = monitoredRoot.standardizedFileURL.path
        self.probe = probe
        super.init()
    }

    override func fileExists(atPath path: String) -> Bool {
        if path == monitoredRoot {
            probe.recordProbe()
        }
        return super.fileExists(atPath: path)
    }

    override func fileExists(
        atPath path: String,
        isDirectory: UnsafeMutablePointer<ObjCBool>?
    ) -> Bool {
        if path == monitoredRoot {
            probe.recordVerificationRoot()
        }
        return super.fileExists(atPath: path, isDirectory: isDirectory)
    }
}

private final class SurvivorValidationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTotalProbeCount = 0
    private var storedVerificationRootCount = 0

    var totalProbeCount: Int { lock.withLock { storedTotalProbeCount } }
    var verificationRootCount: Int { lock.withLock { storedVerificationRootCount } }

    func recordProbe() {
        lock.withLock { storedTotalProbeCount += 1 }
    }

    func recordVerificationRoot() {
        lock.withLock {
            storedTotalProbeCount += 1
            storedVerificationRootCount += 1
        }
    }
}

private struct StepFailingTransferStore: VaultTransferStoring, Sendable {
    func save(_ record: VaultTransferRecord) throws {}
    func record(id: UUID) throws -> VaultTransferRecord? {
        throw SQLiteArchiveDatabase.StoreError.step("injected SQLITE_BUSY")
    }
    func recoverableRecords() throws -> [VaultTransferRecord] {
        throw SQLiteArchiveDatabase.StoreError.step("injected SQLITE_BUSY")
    }
    func allTransferRecords() throws -> [VaultTransferRecord] {
        throw SQLiteArchiveDatabase.StoreError.step("injected SQLITE_BUSY")
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
        try snapshot(at: source)
    }

    func snapshot(at root: URL) throws -> [String: Data] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys))
        var result: [String: Data] = [:]
        while let url = enumerator?.nextObject() as? URL {
            if try url.resourceValues(forKeys: keys).isRegularFile == true {
                result[String(url.path.dropFirst(root.path.count + 1))] = try Data(contentsOf: url)
            }
        }
        return result
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private actor PendingUploadProvider: ArchiveStorageProvider {
    let pendingAtPromotion: Bool
    var finished = false
    private(set) var calls = 0
    init(pendingAtPromotion: Bool) { self.pendingAtPromotion = pendingAtPromotion }
    func finish() { finished = true }
    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: true, supportsMaterialization: false, supportsEviction: false)
    }
    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        calls += 1
        if !finished && (!pendingAtPromotion || location.path.contains("/generations/")) {
            throw FileProviderArchiveStorageError.uploadPending
        }
        return .syncedToProvider
    }
    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}
