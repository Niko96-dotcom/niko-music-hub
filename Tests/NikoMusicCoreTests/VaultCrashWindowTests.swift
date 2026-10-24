import XCTest
@testable import NikoMusicCore

/// One crash-then-launch test per window between a side effect and the save
/// that records it. Engine A stops at the window as if the process died;
/// engine B, fresh on the same journal, runs launch recovery twice. Each test
/// pins today's journal state, Active folder, generation and the file
/// operations the relaunch replays. The engines save through
/// `VaultEdgeRecordingStore`, so every edge they make must be an observed one.
final class VaultCrashWindowTests: XCTestCase {
    // MARK: - Archive

    func testCrashAfterTheCopyBeforeItsManifestIsSavedCopiesAgainAtLaunch() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let original = try fixture.snapshot(fixture.source)

        let crashed = try await fixture.crash(at: .copiedBeforeManifestSave) { engine in
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
        }

        XCTAssertEqual(crashed.state, .copyingToArchiveStaging)
        XCTAssertNil(crashed.manifest, "the finished copy has no saved manifest yet")
        XCTAssertTrue(FileManager.default.fileExists(atPath: crashed.stagingURL.path))
        let relaunch = try await fixture.launchTwice()
        XCTAssertEqual(relaunch.first.map(\.state), [.archiveVerified])
        // Without its manifest the copy proves nothing: the staging folder is
        // removed and the project copied again before promotion.
        XCTAssertEqual(relaunch.firstOperations.first, "remove \(crashed.stagingURL.lastPathComponent)")
        XCTAssertTrue(relaunch.firstOperations.contains { $0.hasPrefix("copy ") })
        XCTAssertEqual(relaunch.firstOperations.last, "move \(crashed.destinationURL.lastPathComponent)")
        relaunch.assertSecondLaunchChangesNothing()
        XCTAssertEqual(try fixture.snapshot(fixture.source), original)
        try fixture.assertOnlyGeneration(of: crashed)
        fixture.assertEdgesWereObserved()
    }

    func testCrashAfterTheGenerationRenameFinishesWithoutCopyingAgain() async throws {
        for window in [VaultTransferCrashWindow.renamedBeforeDurabilitySave, .durabilitySavedBeforeVerifiedSave] {
            let fixture = try TransferCrashFixture()
            defer { fixture.remove() }
            let original = try fixture.snapshot(fixture.source)

            let crashed = try await fixture.crash(at: window) { engine in
                _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            }

            XCTAssertEqual(crashed.state, .promotingArchiveGeneration, "\(window)")
            XCTAssertEqual(crashed.durability, .verifiedLocal, "\(window)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: crashed.destinationURL.path), "\(window)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: crashed.stagingURL.path), "\(window)")
            let relaunch = try await fixture.launchTwice()
            XCTAssertEqual(relaunch.first.map(\.state), [.archiveVerified], "\(window)")
            XCTAssertEqual(relaunch.firstOperations, [], "the renamed generation is verified, not rebuilt (\(window))")
            relaunch.assertSecondLaunchChangesNothing()
            XCTAssertEqual(try fixture.snapshot(fixture.source), original, "\(window)")
            try fixture.assertOnlyGeneration(of: crashed)
            fixture.assertEdgesWereObserved()
        }
    }

    // MARK: - Removal

    func testCrashAfterTheRemovalReproofKeepsTheActiveFolderAndTheVerifiedCopy() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let verified = try await fixture.verifiedArchive()
        let original = try fixture.snapshot(fixture.source)

        let crashed = try await fixture.crash(at: .reproofSavedBeforeRemovalSave) { engine in
            _ = try await engine.removeActiveCopy(after: verified)
        }

        XCTAssertEqual(crashed.state, .archiveVerified)
        XCTAssertEqual(crashed.durability, .verifiedLocal)
        let relaunch = try await fixture.launchTwice()
        XCTAssertTrue(relaunch.first.isEmpty, "a verified copy is not launch work")
        XCTAssertEqual(relaunch.firstOperations, [])
        relaunch.assertSecondLaunchChangesNothing()
        XCTAssertEqual(try fixture.store.record(id: verified.id)?.state, .archiveVerified)
        XCTAssertEqual(try fixture.snapshot(fixture.source), original)
        try fixture.assertOnlyGeneration(of: crashed)
        fixture.assertEdgesWereObserved()
    }

    func testCrashBeforeRemoveItemNeedsReviewAndKeepsTheActiveFolder() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let verified = try await fixture.verifiedArchive()
        let original = try fixture.snapshot(fixture.source)

        let crashed = try await fixture.crash(at: .removalBeforeRemoveItem) { engine in
            _ = try await engine.removeActiveCopy(after: verified)
        }

        XCTAssertEqual(crashed.state, .removingActiveCopy)
        let relaunch = try await fixture.launchTwice()
        XCTAssertEqual(relaunch.first.map(\.state), [.recoveryRequired])
        XCTAssertEqual(relaunch.first.first?.error?.origin, .removingActiveCopy)
        XCTAssertEqual(relaunch.firstOperations, [], "launch never resumes a removal")
        relaunch.assertSecondLaunchChangesNothing()
        XCTAssertEqual(try fixture.snapshot(fixture.source), original)
        try fixture.assertOnlyGeneration(of: crashed)
        XCTAssertEqual(fixture.store.transferEdges.last, .init(.removingActiveCopy, .recoveryRequired))
        fixture.assertEdgesWereObserved()
    }

    func testCrashAfterRemoveItemNeedsReviewAndTheVaultCopyStaysRecoverable() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let verified = try await fixture.verifiedArchive()

        let crashed = try await fixture.crash(at: .removalAfterRemoveItem) { engine in
            _ = try await engine.removeActiveCopy(after: verified)
        }

        XCTAssertEqual(crashed.state, .removingActiveCopy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        let relaunch = try await fixture.launchTwice()
        XCTAssertEqual(relaunch.first.map(\.state), [.recoveryRequired])
        XCTAssertEqual(relaunch.first.first?.error?.origin, .removingActiveCopy)
        XCTAssertEqual(relaunch.firstOperations, [])
        relaunch.assertSecondLaunchChangesNothing()
        try fixture.assertOnlyGeneration(of: crashed)
        let recovered = try await fixture.engine().recoverInterruptedRemoval(id: verified.id)
        XCTAssertEqual(recovered.state, .archiveVerified)
        XCTAssertNil(recovered.preservedActiveCopies, "nothing was left to preserve")
        fixture.assertEdgesWereObserved()
    }

    func testCrashAfterEvictionNeedsReview() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let verified = try await fixture.verifiedArchive()

        let crashed = try await fixture.crash(at: .evictedBeforeSave) { engine in
            _ = try await engine.removeActiveCopy(after: verified)
        }

        XCTAssertEqual(crashed.state, .evictingProviderCache)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        let relaunch = try await fixture.launchTwice()
        XCTAssertEqual(relaunch.first.map(\.state), [.recoveryRequired])
        XCTAssertEqual(relaunch.first.first?.error?.origin, .evictingProviderCache)
        XCTAssertEqual(relaunch.firstOperations, [])
        relaunch.assertSecondLaunchChangesNothing()
        try fixture.assertOnlyGeneration(of: crashed)
        XCTAssertEqual(fixture.store.transferEdges.last, .init(.evictingProviderCache, .recoveryRequired))
        fixture.assertEdgesWereObserved()
    }

    // MARK: - Interrupted-removal recovery

    func testCrashBeforeThePreservingMoveKeepsTheActiveFolderAndItsRecordedPath() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let interrupted = try await fixture.interruptedRemoval()
        let original = try fixture.snapshot(fixture.source)

        let crashed = try await fixture.crash(at: .recoveryBeforePreservingMove) { engine in
            _ = try await engine.recoverInterruptedRemoval(id: interrupted.id)
        }

        XCTAssertEqual(crashed.state, .recoveryRequired)
        let recordedPath = try XCTUnwrap(crashed.preservedActiveCopies?.first)
        XCTAssertEqual(crashed.preservedActiveCopies?.count, 1, "the path is saved before the move")
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedPath.path))
        XCTAssertEqual(try fixture.snapshot(fixture.source), original)
        let relaunch = try await fixture.launchTwice()
        XCTAssertTrue(relaunch.first.isEmpty, "review waits for the person")
        XCTAssertEqual(relaunch.firstOperations, [])
        relaunch.assertSecondLaunchChangesNothing()

        let recovered = try await fixture.engine().recoverInterruptedRemoval(id: interrupted.id)
        XCTAssertEqual(recovered.state, .archiveVerified)
        // The retry records a fresh path; the first one was never created.
        XCTAssertEqual(recovered.preservedActiveCopies?.first, recordedPath)
        let preserved = try XCTUnwrap(recovered.preservedActiveCopies?.last)
        XCTAssertEqual(recovered.preservedActiveCopies?.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedPath.path))
        XCTAssertEqual(try fixture.snapshot(preserved), original)
        fixture.assertEdgesWereObserved()
    }

    func testCrashBeforeTheRecoverySaveLeavesReviewOpenAndKeepsEveryCopy() async throws {
        for activeFolder in ["preserved", "missing"] {
            let fixture = try TransferCrashFixture()
            defer { fixture.remove() }
            let interrupted = try await fixture.interruptedRemoval()
            let original = try fixture.snapshot(fixture.source)
            if activeFolder == "missing" { try FileManager.default.removeItem(at: fixture.source) }

            let crashed = try await fixture.crash(at: .recoveryBeforeVerifiedSave) { engine in
                _ = try await engine.recoverInterruptedRemoval(id: interrupted.id)
            }

            XCTAssertEqual(crashed.state, .recoveryRequired, activeFolder)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path), activeFolder)
            if activeFolder == "preserved" {
                let preserved = try XCTUnwrap(crashed.preservedActiveCopies?.last, activeFolder)
                XCTAssertEqual(try fixture.snapshot(preserved), original, activeFolder)
            } else {
                XCTAssertNil(crashed.preservedActiveCopies, activeFolder)
            }
            let relaunch = try await fixture.launchTwice()
            XCTAssertTrue(relaunch.first.isEmpty, activeFolder)
            XCTAssertEqual(relaunch.firstOperations, [], activeFolder)
            relaunch.assertSecondLaunchChangesNothing()

            let recovered = try await fixture.engine().recoverInterruptedRemoval(id: interrupted.id)
            XCTAssertEqual(recovered.state, .archiveVerified, activeFolder)
            XCTAssertEqual(recovered.preservedActiveCopies, crashed.preservedActiveCopies, activeFolder)
            try fixture.assertOnlyGeneration(of: crashed)
            fixture.assertEdgesWereObserved()
        }
    }

    // MARK: - Launch writes

    /// Survivor retirement, the legacy normalization and the destructive-phase
    /// normalization have no side effect after their save in the launch pass,
    /// so a crash right after them leaves the journal of a finished pass.
    /// Engine A's pass makes the write; engine B's two launches must not undo
    /// or replay anything. (The destructive-phase normalization is the first
    /// launch of the removal tests above.)
    func testRelaunchAfterSurvivorRetirementKeepsTheOlderTransferRetired() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let older = try fixture.failedRecord(origin: .awaitingProviderDurability, retryCount: 1, createdAt: Date(timeIntervalSince1970: 40_000))
        let survivor = try fixture.verifiedSurvivor(for: older, createdAt: Date(timeIntervalSince1970: 40_010))

        _ = try await fixture.engine().recoverAtLaunch()
        XCTAssertEqual(try fixture.store.record(id: older.id)?.state, .superseded)

        let relaunch = try await fixture.launchTwice()
        XCTAssertTrue(relaunch.first.isEmpty)
        XCTAssertEqual(relaunch.firstOperations, [], "a retired transfer never copies again")
        relaunch.assertSecondLaunchChangesNothing()
        let retired = try XCTUnwrap(fixture.store.record(id: older.id))
        XCTAssertEqual(retired.state, .superseded)
        XCTAssertEqual(retired.supersededBy, survivor.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: older.stagingURL.path), "retirement deletes nothing")
        XCTAssertEqual(fixture.store.transferEdges, [.init(.failedRecoverable, .superseded)])
        fixture.assertEdgesWereObserved()
    }

    func testRelaunchAfterTheLegacyDestructiveFailureNormalizationChangesNothing() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let legacy = try fixture.failedRecord(origin: .removingActiveCopy, retryCount: 1, createdAt: Date(timeIntervalSince1970: 41_000))

        _ = try await fixture.engine().recoverAtLaunch()
        XCTAssertEqual(try fixture.store.record(id: legacy.id)?.state, .recoveryRequired)

        let relaunch = try await fixture.launchTwice()
        XCTAssertTrue(relaunch.first.isEmpty)
        XCTAssertEqual(relaunch.firstOperations, [])
        relaunch.assertSecondLaunchChangesNothing()
        XCTAssertEqual(try fixture.store.record(id: legacy.id)?.error?.origin, .removingActiveCopy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.stagingURL.path))
        XCTAssertEqual(fixture.store.transferEdges, [.init(.failedRecoverable, .recoveryRequired)])
        fixture.assertEdgesWereObserved()
    }

    /// The retry rewinds are saved before `execute` starts, and the resumed
    /// phase's fault point fires before its first side effect: stopping there
    /// is a crash right after the rewind.
    func testCrashRightAfterTheLaunchRetryRewindResumesWithoutCopyingAgain() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let failed = try fixture.failedRecord(origin: .awaitingProviderDurability, retryCount: 1, createdAt: Date())
        let original = try fixture.snapshot(fixture.source)

        let crashed = try await fixture.crash(atPhase: .awaitingProviderDurability) { engine in
            _ = await engine.recoverAtLaunch()
        }

        XCTAssertEqual(crashed.state, .awaitingProviderDurability)
        XCTAssertNil(crashed.error)
        let relaunch = try await fixture.launchTwice()
        XCTAssertEqual(relaunch.first.map(\.state), [.archiveVerified])
        XCTAssertEqual(relaunch.firstOperations, ["move \(failed.destinationURL.lastPathComponent)"], "the staged copy is promoted, not made again")
        relaunch.assertSecondLaunchChangesNothing()
        XCTAssertEqual(try fixture.snapshot(fixture.source), original)
        try fixture.assertOnlyGeneration(of: failed)
        fixture.assertEdgesWereObserved()
    }

    func testCrashRightAfterTheExplicitRetryRewindResumesAtLaunch() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let failed = try fixture.failedRecord(origin: .awaitingProviderDurability, retryCount: 5, createdAt: Date())

        let crashed = try await fixture.crash(atPhase: .awaitingProviderDurability) { engine in
            _ = await engine.retryRecoverableTransfer(id: failed.id)
        }

        XCTAssertEqual(crashed.state, .awaitingProviderDurability)
        XCTAssertEqual(crashed.retryCount, 5, "the explicit retry keeps the spent budget")
        let relaunch = try await fixture.launchTwice()
        XCTAssertEqual(relaunch.first.map(\.state), [.archiveVerified])
        XCTAssertEqual(relaunch.firstOperations, ["move \(failed.destinationURL.lastPathComponent)"])
        relaunch.assertSecondLaunchChangesNothing()
        try fixture.assertOnlyGeneration(of: failed)
        fixture.assertEdgesWereObserved()
    }

    // MARK: - Restore

    func testCrashAfterTheRestoreRenameFinishesAtLaunchWithoutCopyingAgain() async throws {
        let fixture = try RestoreCrashFixture()
        defer { fixture.remove() }

        let crashed = try await fixture.crash(at: .renamedBeforePhaseSave)

        XCTAssertEqual(crashed.phase, .promotingActiveCopy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: crashed.destinationURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: crashed.stagingURL.path))
        let relaunch = await fixture.launchTwice()
        XCTAssertNotNil(relaunch.first.first?.completedAt)
        XCTAssertEqual(relaunch.firstOperations, [], "the renamed folder is verified, not copied again")
        XCTAssertTrue(relaunch.second.isEmpty)
        XCTAssertEqual(relaunch.secondOperations, [])
        XCTAssertEqual(fixture.catalog.count, 1)
        XCTAssertEqual(fixture.workspace.opened.count, 1)
        try VaultManifestBuilder().verify(fixture.manifest, at: crashed.destinationURL)
        fixture.assertEdgesWereObserved()
    }

    func testCrashAfterTheCatalogWriteWritesTheCatalogAgainAtLaunch() async throws {
        let fixture = try RestoreCrashFixture()
        defer { fixture.remove() }

        let crashed = try await fixture.crash(at: .catalogWrittenBeforeSave)

        XCTAssertEqual(crashed.phase, .persistingActiveLocation)
        XCTAssertFalse(crashed.catalogLocationPersisted)
        XCTAssertEqual(fixture.catalog.count, 1)
        let relaunch = await fixture.launchTwice()
        XCTAssertNotNil(relaunch.first.first?.completedAt)
        XCTAssertEqual(relaunch.firstOperations, [])
        XCTAssertTrue(relaunch.second.isEmpty)
        // The location write is repeated; it stores the same location again.
        XCTAssertEqual(fixture.catalog.count, 2)
        XCTAssertEqual(fixture.workspace.opened.count, 1)
        fixture.assertEdgesWereObserved()
    }

    /// Known non-atomic pair: the open is not part of the journal, so a crash
    /// between it and `completedAt` opens the project again at the next launch.
    func testCrashAfterTheOpenOpensTheProjectAgainAtLaunch() async throws {
        let fixture = try RestoreCrashFixture()
        defer { fixture.remove() }

        let crashed = try await fixture.crash(at: .openedBeforeCompletionSave)

        XCTAssertEqual(crashed.phase, .openingInCubase)
        XCTAssertNil(crashed.completedAt)
        XCTAssertEqual(fixture.workspace.opened.count, 1)
        let relaunch = await fixture.launchTwice()
        XCTAssertNotNil(relaunch.first.first?.completedAt)
        XCTAssertEqual(relaunch.firstOperations, [])
        XCTAssertTrue(relaunch.second.isEmpty)
        XCTAssertEqual(fixture.workspace.opened.count, 2, "today the project opens a second time")
        XCTAssertEqual(fixture.catalog.count, 1)
        fixture.assertEdgesWereObserved()
    }
}

// MARK: - Fixtures

private struct TransferRelaunch {
    let first: [VaultTransferRecord]
    let firstOperations: [String]
    let second: [VaultTransferRecord]
    let secondOperations: [String]
    let journalAfterFirst: [VaultTransferRecord]
    let journalAfterSecond: [VaultTransferRecord]

    func assertSecondLaunchChangesNothing(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(secondOperations, [], "the second launch touched files", file: file, line: line)
        XCTAssertEqual(
            journalAfterSecond.map(\.state), journalAfterFirst.map(\.state),
            "the second launch changed a state", file: file, line: line
        )
        XCTAssertTrue(
            second.allSatisfy { record in first.contains { $0.id == record.id && $0.state == record.state } },
            "the second launch resumed work", file: file, line: line
        )
    }
}

private final class TransferCrashFixture {
    let root: URL
    let active: URL
    let archive: URL
    let source: URL
    let store: VaultEdgeRecordingStore
    let files = VaultMutationLog()

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-crash-window-\(UUID().uuidString)", isDirectory: true)
        active = root.appendingPathComponent("Active", isDirectory: true)
        archive = root.appendingPathComponent("Archive", isDirectory: true)
        source = active.appendingPathComponent("Artist Song", isDirectory: true)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("Audio", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("cubase-project".utf8).write(to: source.appendingPathComponent("Artist Song.cpr"))
        try Data((0..<4096).map { UInt8($0 % 251) }).write(to: source.appendingPathComponent("Audio/take.wav"))
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        store = try VaultEdgeRecordingStore(databaseURL: root.appendingPathComponent("state/vault.sqlite"))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func engine(
        fault: LocalVaultTransferEngine.FaultInjector? = nil,
        crash: LocalVaultTransferEngine.CrashInjector? = nil
    ) throws -> LocalVaultTransferEngine {
        try LocalVaultTransferEngine(
            activeRoot: active,
            archiveRoot: archive,
            store: store,
            fileManager: VaultMutationRecordingFileManager(log: files),
            faultInjector: fault,
            crashInjector: crash,
            writeAdmission: { _, operation in try await operation() },
            removalAdmission: { _ in }
        )
    }

    /// Engine A runs `operation` and stops at `window`; returns the record as
    /// the journal held it there.
    func crash(
        at window: VaultTransferCrashWindow,
        _ operation: (LocalVaultTransferEngine) async throws -> Void
    ) async throws -> VaultTransferRecord {
        let capture = VaultCrashCapture<VaultTransferRecord>()
        let store = self.store
        let engine = try self.engine(crash: { observed, record in
            guard observed == window else { return }
            capture.value = try store.record(id: record.id)
            throw VaultTransferInterruption()
        })
        do { try await operation(engine) } catch is VaultTransferInterruption {}
        return try XCTUnwrap(capture.value, "engine A never reached \(window)")
    }

    /// Like `crash(at:)`, at a phase fault point.
    func crash(
        atPhase point: VaultTransferFaultPoint,
        _ operation: (LocalVaultTransferEngine) async throws -> Void
    ) async throws -> VaultTransferRecord {
        let capture = VaultCrashCapture<VaultTransferRecord>()
        let store = self.store
        let engine = try self.engine(fault: { observed, record in
            guard observed == point else { return }
            capture.value = try store.record(id: record.id)
            throw VaultTransferInterruption()
        })
        do { try await operation(engine) } catch is VaultTransferInterruption {}
        return try XCTUnwrap(capture.value, "engine A never reached \(point)")
    }

    /// Engine B, fresh on the same journal, runs launch recovery twice.
    func launchTwice() async throws -> TransferRelaunch {
        let engine = try self.engine()
        files.reset()
        let first = await engine.recoverAtLaunch()
        let firstOperations = files.operations
        let journalAfterFirst = try store.allTransferRecords().sorted { $0.id.uuidString < $1.id.uuidString }
        files.reset()
        let second = await engine.recoverAtLaunch()
        return TransferRelaunch(
            first: first,
            firstOperations: firstOperations,
            second: second,
            secondOperations: files.operations,
            journalAfterFirst: journalAfterFirst,
            journalAfterSecond: try store.allTransferRecords().sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    func verifiedArchive() async throws -> VaultTransferRecord {
        try await engine().archive(projectID: ProjectID(), sourceURL: source)
    }

    /// A verified archive whose removal stopped; saved past the recorder,
    /// since the test sets it up.
    func interruptedRemoval() async throws -> VaultTransferRecord {
        var record = try await verifiedArchive()
        record.state = .recoveryRequired
        record.error = VaultTransferError(origin: .removingActiveCopy, reason: .unknown, message: "Interrupted")
        try store.base.save(record)
        return record
    }

    /// A failed transfer with a complete staging copy, saved past the recorder.
    func failedRecord(
        origin: VaultTransferState,
        retryCount: Int,
        createdAt: Date
    ) throws -> VaultTransferRecord {
        let projectID = ProjectID()
        let transferID = UUID()
        let staging = VaultFolders.staging(in: archive, projectID: projectID, operationID: transferID)
        try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: staging)
        let manifest = try VaultManifestBuilder().build(at: staging)
        var record = VaultTransferRecord(
            id: transferID,
            projectID: projectID,
            sourceURL: source,
            stagingURL: staging,
            destinationURL: VaultFolders.generation(in: archive, projectID: projectID, transferID: transferID),
            state: .failedRecoverable,
            createdAt: createdAt
        )
        record.updatedAt = createdAt
        record.retryCount = retryCount
        record.manifestID = manifest.id
        record.manifest = manifest
        record.completedBytes = manifest.totalBytes
        record.totalBytes = manifest.totalBytes
        record.error = VaultTransferError(origin: origin, reason: .unknown, message: "stopped")
        try store.base.save(record)
        return record
    }

    /// A newer verified generation for the same project, saved past the recorder.
    func verifiedSurvivor(for older: VaultTransferRecord, createdAt: Date) throws -> VaultTransferRecord {
        let survivorID = UUID()
        let generation = VaultFolders.generation(in: archive, projectID: older.projectID, transferID: survivorID)
        try FileManager.default.createDirectory(at: generation.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: generation)
        let manifest = try VaultManifestBuilder().build(at: generation)
        var survivor = VaultTransferRecord(
            id: survivorID,
            projectID: older.projectID,
            sourceURL: source,
            stagingURL: VaultFolders.staging(in: archive, projectID: older.projectID, operationID: survivorID),
            destinationURL: generation,
            state: .archiveVerified,
            createdAt: createdAt
        )
        survivor.updatedAt = createdAt
        survivor.manifestID = manifest.id
        survivor.manifest = manifest
        survivor.durability = .verifiedLocal
        try store.base.save(survivor)
        return survivor
    }

    func snapshot(_ folder: URL) throws -> [String: Data] {
        try VaultCrashSnapshot.files(at: folder)
    }

    /// The project's generations folder holds exactly this record's
    /// generation, and its bytes match the record's manifest.
    func assertOnlyGeneration(of record: VaultTransferRecord, file: StaticString = #filePath, line: UInt = #line) throws {
        let generations = try FileManager.default.contentsOfDirectory(
            at: record.destinationURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(generations.map(\.lastPathComponent), [record.destinationURL.lastPathComponent], file: file, line: line)
        let saved = try XCTUnwrap(store.record(id: record.id), file: file, line: line)
        try VaultManifestBuilder().verifyArchive(XCTUnwrap(saved.manifest, file: file, line: line), at: record.destinationURL)
    }

    func assertEdgesWereObserved(file: StaticString = #filePath, line: UInt = #line) {
        let unobserved = Set(store.transferEdges).subtracting(VaultObservedEdges.transfer)
        XCTAssertTrue(unobserved.isEmpty, "edges nobody observed: \(unobserved)", file: file, line: line)
    }
}

private struct RestoreRelaunch {
    let first: [VaultRestoreRecord]
    let firstOperations: [String]
    let second: [VaultRestoreRecord]
    let secondOperations: [String]
}

private final class RestoreCrashFixture {
    let root: URL
    let active: URL
    let archive: URL
    let generation: URL
    let activeRootID = UUID()
    let projectID = ProjectID()
    let manifest: VaultManifest
    let store: VaultEdgeRecordingStore
    let files = VaultMutationLog()
    let catalog = RestoreCatalogLog()
    let workspace = RestoreWorkspaceLog()

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-restore-crash-\(UUID().uuidString)", isDirectory: true)
        active = root.appendingPathComponent("Active", isDirectory: true)
        archive = root.appendingPathComponent("Archive", isDirectory: true)
        generation = archive.appendingPathComponent("generations/verified", isDirectory: true)
        try FileManager.default.createDirectory(
            at: generation.appendingPathComponent("Audio", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        try Data("synthetic-project".utf8).write(to: generation.appendingPathComponent("Synthetic Song.cpr"))
        try Data((0..<4096).map { UInt8($0 % 251) }).write(to: generation.appendingPathComponent("Audio/take.wav"))
        manifest = try VaultManifestBuilder().build(at: generation)
        store = try VaultEdgeRecordingStore(databaseURL: root.appendingPathComponent("State/vault.sqlite"))
        var archiveRecord = VaultTransferRecord(
            projectID: projectID,
            sourceURL: active.appendingPathComponent("former-active"),
            stagingURL: archive.appendingPathComponent(".niko-staging/old"),
            destinationURL: generation,
            state: .archiveVerified
        )
        archiveRecord.manifestID = manifest.id
        archiveRecord.manifest = manifest
        archiveRecord.durability = .verifiedLocal
        try store.base.save(archiveRecord)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func engine(crash: LocalVaultRestoreEngine.CrashInjector? = nil) -> LocalVaultRestoreEngine {
        LocalVaultRestoreEngine(
            activeRoot: active,
            archiveRoot: archive,
            activeRootID: activeRootID,
            resolver: store,
            store: store,
            projectionStore: store,
            provider: LocalFolderArchiveStorage(root: archive, fileManager: VaultMutationRecordingFileManager(log: files)),
            catalog: catalog,
            projectOpener: SafeVaultProjectOpener(workspace: workspace),
            fileManager: VaultMutationRecordingFileManager(log: files),
            crashInjector: crash,
            writeAdmission: { _, operation in try await operation() }
        )
    }

    /// Engine A restores and stops at `window`; returns the restore as the
    /// journal held it there.
    func crash(at window: VaultRestoreCrashWindow) async throws -> VaultRestoreRecord {
        let capture = VaultCrashCapture<VaultRestoreRecord>()
        let store = self.store
        let engine = self.engine(crash: { observed, record in
            guard observed == window else { return }
            capture.value = try store.restoreRecord(id: record.id)
            throw VaultTransferInterruption()
        })
        do {
            _ = try await engine.restoreAndOpen(projectID: projectID, destinationRelativePath: "Recovered/Synthetic Song")
        } catch is VaultTransferInterruption {}
        return try XCTUnwrap(capture.value, "engine A never reached \(window)")
    }

    func launchTwice() async -> RestoreRelaunch {
        let engine = self.engine()
        files.reset()
        let first = await engine.recoverAtLaunch()
        let firstOperations = files.operations
        files.reset()
        let second = await engine.recoverAtLaunch()
        return RestoreRelaunch(first: first, firstOperations: firstOperations, second: second, secondOperations: files.operations)
    }

    func assertEdgesWereObserved(file: StaticString = #filePath, line: UInt = #line) {
        let unobserved = Set(store.restoreEdges).subtracting(VaultObservedEdges.restore)
        XCTAssertTrue(unobserved.isEmpty, "edges nobody observed: \(unobserved)", file: file, line: line)
    }
}

private final class VaultCrashCapture<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private final class RestoreCatalogLog: ActiveProjectLocationPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var writes = 0

    var count: Int { lock.withLock { writes } }

    func persistActiveLocation(projectID: ProjectID, location: ProjectLocation) throws {
        lock.withLock { writes += 1 }
    }
}

private final class RestoreWorkspaceLog: WorkspaceOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var storedOpened: [URL] = []

    var opened: [URL] { lock.withLock { storedOpened } }

    func open(_ url: URL) -> Bool {
        lock.withLock { storedOpened.append(url) }
        return true
    }

    func revealInFinder(_ url: URL) {}
}

private enum VaultCrashSnapshot {
    static func files(at folder: URL) throws -> [String: Data] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys))
        let prefix = folder.standardizedFileURL.pathComponents.count
        var result: [String: Data] = [:]
        while let url = enumerator?.nextObject() as? URL {
            if try url.resourceValues(forKeys: keys).isRegularFile == true {
                let relative = url.standardizedFileURL.pathComponents.dropFirst(prefix).joined(separator: "/")
                result[relative] = try Data(contentsOf: url)
            }
        }
        return result
    }
}
