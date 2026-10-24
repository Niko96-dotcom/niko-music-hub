import CryptoKit
import XCTest
@testable import NikoMusicCore

/// One crash-then-launch test per window between a side effect and the save
/// that records it. Engine A stops at the window as if the process died;
/// engine B, fresh on the same journal, runs launch recovery twice. Each test
/// pins today's journal state, Active folder, generation and the file
/// operations the relaunch replays. The engines save through
/// `VaultEdgeRecordingStore`, so every edge they make must be an observed one.
/// Two more tests show that an edge the state table does not list throws
/// before anything is saved.
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

    /// A newer verified generation does not show that an interrupted removal
    /// kept the Active folder, so retirement hands the removal to the person's
    /// review instead, and their recovery works as for any interrupted removal.
    /// An archive-phase failure of the same project still retires.
    func testSurvivorRetirementHandsAnInterruptedRemovalToReview() async throws {
        let removals: [(phase: VaultTransferState, legacyFailure: Bool)] = [
            (.removingActiveCopy, false),
            (.evictingProviderCache, false),
            (.removingActiveCopy, true),
            (.evictingProviderCache, true),
        ]
        for (phase, legacyFailure) in removals {
            let label = legacyFailure ? "legacy failure in \(phase)" : "\(phase)"
            let fixture = try TransferCrashFixture()
            defer { fixture.remove() }
            let removal = try await fixture.stoppedRemoval(in: phase, legacyFailure: legacyFailure)
            let archiveFailure = try fixture.failedRecord(
                origin: .awaitingProviderDurability, retryCount: 1,
                projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(5)
            )
            let survivor = try fixture.verifiedSurvivor(for: removal, createdAt: removal.createdAt.addingTimeInterval(10))

            let relaunch = try await fixture.launchTwice()

            let reviewed = try XCTUnwrap(fixture.store.record(id: removal.id), label)
            XCTAssertEqual(reviewed.state, .recoveryRequired, label)
            XCTAssertEqual(reviewed.error?.origin, phase, label)
            XCTAssertNil(reviewed.supersededBy, label)
            XCTAssertNil(reviewed.nextRetryAt, label)
            XCTAssertEqual(reviewed.manifest, removal.manifest, label)
            XCTAssertEqual(reviewed.durability, removal.durability, label)
            XCTAssertEqual(reviewed.destinationURL, removal.destinationURL, label)
            XCTAssertEqual(relaunch.first.map(\.id), [removal.id], label)
            XCTAssertEqual(relaunch.firstOperations, [], "launch never resumes or retires a removal (\(label))")
            relaunch.assertSecondLaunchChangesNothing()
            let retired = try XCTUnwrap(fixture.store.record(id: archiveFailure.id), label)
            XCTAssertEqual(retired.state, .superseded, label)
            XCTAssertEqual(retired.supersededBy, survivor.id, label)

            let recovered = try await fixture.engine().recoverInterruptedRemoval(id: removal.id)
            XCTAssertEqual(recovered.state, .archiveVerified, label)
            fixture.assertEdgesWereObserved()
        }
    }

    /// The later launch normalization sees only the newest record of a
    /// project, so retirement decides an older interrupted removal itself.
    func testSurvivorRetirementHandsAnOlderInterruptedRemovalToReviewBesideANewerFailure() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let removal = try await fixture.stoppedRemoval(in: .removingActiveCopy)
        let survivor = try fixture.verifiedSurvivor(for: removal, createdAt: removal.createdAt.addingTimeInterval(10))
        let newerFailure = try fixture.failedRecord(
            origin: .awaitingProviderDurability, retryCount: 5,
            projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(20)
        )
        let savedFailure = try fixture.store.record(id: newerFailure.id)

        let relaunch = try await fixture.launchTwice()

        let reviewed = try XCTUnwrap(fixture.store.record(id: removal.id))
        XCTAssertEqual(reviewed.state, .recoveryRequired)
        XCTAssertEqual(reviewed.error?.origin, .removingActiveCopy)
        XCTAssertNil(reviewed.supersededBy)
        XCTAssertEqual(try fixture.store.record(id: newerFailure.id), savedFailure, "a failure newer than the survivor stays")
        XCTAssertEqual(try fixture.store.record(id: survivor.id)?.state, .archiveVerified)
        XCTAssertEqual(relaunch.firstOperations, [])
        relaunch.assertSecondLaunchChangesNothing()
        XCTAssertEqual(fixture.store.transferEdges.last, .init(.removingActiveCopy, .recoveryRequired))
        fixture.assertEdgesWereObserved()
    }

    /// Both removal phases, and the legacy V1 failure saved in each.
    private static let interruptedRemovals: [(phase: VaultTransferState, legacyFailure: Bool)] = [
        (.removingActiveCopy, false),
        (.evictingProviderCache, false),
        (.removingActiveCopy, true),
        (.evictingProviderCache, true),
    ]

    /// Launch hands every interrupted removal to review before survivor
    /// retirement, so a survivor whose checks fail changes nothing for it. The
    /// older archive failure shows that the survivor retired nothing.
    func testLaunchHandsAnOlderInterruptedRemovalToReviewWhenTheSurvivorChecksFail() async throws {
        for check in ["fresh durability", "generation bytes", "journal proof"] {
            let fixture = try TransferCrashFixture()
            defer { fixture.remove() }
            let removal = try await fixture.stoppedRemoval(in: .removingActiveCopy)
            let archiveFailure = try fixture.failedRecord(
                origin: .awaitingProviderDurability, retryCount: 5,
                projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(5)
            )
            var survivor = try fixture.verifiedSurvivor(for: removal, createdAt: removal.createdAt.addingTimeInterval(10))
            let newerFailure = try fixture.failedRecord(
                origin: .awaitingProviderDurability, retryCount: 5,
                projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(20)
            )
            switch check {
            case "fresh durability":
                // A local generation that claims a cloud sync: the fresh local
                // proof does not match it.
                survivor.durability = .syncedToProvider
                try fixture.store.base.save(survivor)
            case "generation bytes":
                try Data("changed".utf8).write(to: survivor.destinationURL.appendingPathComponent("Artist Song.cpr"))
            default:
                fixture.store.failRecoveryPersistenceProofs()
            }
            let savedArchiveFailure = try fixture.store.record(id: archiveFailure.id)
            let savedNewerFailure = try fixture.store.record(id: newerFailure.id)
            let setupEdges = fixture.store.transferEdges.count

            let relaunch = try await fixture.launchTwice()

            let reviewed = try XCTUnwrap(fixture.store.record(id: removal.id), check)
            XCTAssertEqual(reviewed.state, .recoveryRequired, check)
            XCTAssertEqual(reviewed.error?.origin, .removingActiveCopy, check)
            XCTAssertNil(reviewed.supersededBy, check)
            XCTAssertTrue(relaunch.first.contains { $0.id == removal.id && $0.state == .recoveryRequired }, check)
            XCTAssertEqual(try fixture.store.record(id: archiveFailure.id), savedArchiveFailure, "nothing retired (\(check))")
            XCTAssertEqual(try fixture.store.record(id: newerFailure.id), savedNewerFailure, check)
            XCTAssertEqual(relaunch.firstOperations, [], check)
            relaunch.assertSecondLaunchChangesNothing()
            XCTAssertEqual(fixture.store.transferEdges.dropFirst(setupEdges), [.init(.removingActiveCopy, .recoveryRequired)], check)
            fixture.assertEdgesWereObserved()
        }
    }

    /// Without a verified generation, the newest-record pass sees only the
    /// newer record of the project. The older interrupted removal still goes
    /// to review, and the newer record stays as launch leaves it.
    func testLaunchHandsAnOlderInterruptedRemovalToReviewBesideANewerIncompleteRecord() async throws {
        for (phase, legacyFailure) in Self.interruptedRemovals {
            let label = legacyFailure ? "legacy failure in \(phase)" : "\(phase)"
            let fixture = try TransferCrashFixture()
            defer { fixture.remove() }
            let removal = try await fixture.stoppedRemoval(in: phase, legacyFailure: legacyFailure)
            let newerFailure = try fixture.failedRecord(
                origin: .awaitingProviderDurability, retryCount: 5,
                projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(20)
            )
            let savedFailure = try fixture.store.record(id: newerFailure.id)

            let relaunch = try await fixture.launchTwice()

            let reviewed = try XCTUnwrap(fixture.store.record(id: removal.id), label)
            XCTAssertEqual(reviewed.state, .recoveryRequired, label)
            XCTAssertEqual(reviewed.error?.origin, phase, label)
            XCTAssertNil(reviewed.supersededBy, label)
            XCTAssertEqual(reviewed.manifest, removal.manifest, label)
            XCTAssertEqual(reviewed.durability, removal.durability, label)
            XCTAssertEqual(Set(relaunch.first.map(\.id)), [removal.id, newerFailure.id], label)
            XCTAssertEqual(try fixture.store.record(id: newerFailure.id), savedFailure, label)
            XCTAssertEqual(relaunch.firstOperations, [], label)
            relaunch.assertSecondLaunchChangesNothing()

            let recovered = try await fixture.engine().recoverInterruptedRemoval(id: removal.id)
            XCTAssertEqual(recovered.state, .archiveVerified, label)
            fixture.assertEdgesWereObserved()
        }
    }

    /// An unreadable journal row holds every copy, retry and retirement, but
    /// not the journal-only hand-off of an interrupted removal.
    func testLaunchHandsAnOlderInterruptedRemovalToReviewWhileAJournalRowIsUnreadable() async throws {
        for (phase, legacyFailure) in Self.interruptedRemovals {
            let label = legacyFailure ? "legacy failure in \(phase)" : "\(phase)"
            let fixture = try TransferCrashFixture()
            defer { fixture.remove() }
            let removal = try await fixture.stoppedRemoval(in: phase, legacyFailure: legacyFailure)
            // Retryable: without the unreadable row, launch would resume it.
            let newerFailure = try fixture.failedRecord(
                origin: .awaitingProviderDurability, retryCount: 1,
                projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(20)
            )
            let savedFailure = try fixture.store.record(id: newerFailure.id)
            let unreadableID = UUID()
            try UndecodableVaultJournalRow.insertTransfer(
                id: unreadableID,
                state: VaultTransferState.removingActiveCopy.rawValue,
                databaseURL: fixture.databaseURL
            )
            let engine = try fixture.engine()
            fixture.files.reset()

            let firstReport = await engine.recoverAtLaunchReport()
            let first = try XCTUnwrap(firstReport, label)

            let reviewed = try XCTUnwrap(fixture.store.record(id: removal.id), label)
            XCTAssertEqual(reviewed.state, .recoveryRequired, label)
            XCTAssertEqual(reviewed.error?.origin, phase, label)
            XCTAssertNil(reviewed.supersededBy, label)
            XCTAssertEqual(Set(first.records.map(\.id)), [removal.id, newerFailure.id], label)
            XCTAssertEqual(try fixture.store.record(id: newerFailure.id), savedFailure, "the copy waits (\(label))")
            XCTAssertEqual(first.unreadableRows.map(\.id), [unreadableID.uuidString], label)

            let secondReport = await engine.recoverAtLaunchReport()
            let second = try XCTUnwrap(secondReport, label)
            XCTAssertEqual(second.records.map(\.id), [newerFailure.id], label)
            XCTAssertEqual(try fixture.store.record(id: removal.id), reviewed, label)
            XCTAssertEqual(try fixture.store.record(id: newerFailure.id), savedFailure, label)
            XCTAssertEqual(fixture.files.operations, [], label)
            // The undecodable row is reported, never rewritten.
            XCTAssertEqual(try fixture.store.allTransferRecordsReport().unreadableRows.map(\.id), [unreadableID.uuidString], label)
            fixture.assertEdgesWereObserved()
        }
    }

    /// A hand-off whose save throws leaves the removal as the journal holds
    /// it: launch neither resumes, retries nor retires it in that run, and the
    /// next launch hands it to review.
    func testLaunchKeepsAnInterruptedRemovalAsSavedWhenItsReviewSaveFails() async throws {
        for legacyFailure in [false, true] {
            let label = legacyFailure ? "legacy failure" : "removingActiveCopy"
            let fixture = try TransferCrashFixture()
            defer { fixture.remove() }
            let removal = try await fixture.stoppedRemoval(in: .removingActiveCopy, legacyFailure: legacyFailure)
            let archiveFailure = try fixture.failedRecord(
                origin: .awaitingProviderDurability, retryCount: 1,
                projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(5)
            )
            let survivor = try fixture.verifiedSurvivor(for: removal, createdAt: removal.createdAt.addingTimeInterval(10))
            let savedRemoval = try XCTUnwrap(fixture.store.record(id: removal.id), label)
            let setupEdges = fixture.store.transferEdges.count
            fixture.store.failNextSave(of: .recoveryRequired)
            let engine = try fixture.engine()
            fixture.files.reset()

            let firstLaunch = await engine.recoverAtLaunch()

            XCTAssertEqual(try fixture.store.record(id: removal.id), savedRemoval, label)
            XCTAssertEqual(firstLaunch.first { $0.id == removal.id }, savedRemoval, label)
            XCTAssertEqual(fixture.files.operations, [], "nothing resumed (\(label))")
            let retired = try XCTUnwrap(fixture.store.record(id: archiveFailure.id), label)
            XCTAssertEqual(retired.state, .superseded, label)
            XCTAssertEqual(retired.supersededBy, survivor.id, label)
            XCTAssertEqual(fixture.store.transferEdges.dropFirst(setupEdges), [.init(.failedRecoverable, .superseded)], label)

            _ = await engine.recoverAtLaunch()

            let reviewed = try XCTUnwrap(fixture.store.record(id: removal.id), label)
            XCTAssertEqual(reviewed.state, .recoveryRequired, label)
            XCTAssertNil(reviewed.supersededBy, label)
            XCTAssertEqual(fixture.files.operations, [], label)
            fixture.assertEdgesWereObserved()
        }
    }

    // MARK: - Other transfers wait for the removal's review

    /// An interrupted removal may have left the Active folder incomplete. Until
    /// the person recovers it, launch resumes, retries and migrates no other
    /// transfer of the project: each would put bytes of that folder into the
    /// generation a restore uses.
    func testLaunchHoldsANewerRetryableTransferWhileTheProjectsRemovalAwaitsReview() async throws {
        for (phase, legacyFailure) in Self.interruptedRemovals {
            let label = legacyFailure ? "legacy failure in \(phase)" : "\(phase)"
            let fixture = try TransferCrashFixture()
            defer { fixture.remove() }
            let removal = try await fixture.stoppedRemoval(in: phase, legacyFailure: legacyFailure)
            let newer = try fixture.failedRecord(
                origin: .awaitingProviderDurability, retryCount: 1,
                projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(20)
            )
            let held = try fixture.saved(newer)

            let relaunch = try await fixture.launchTwice()

            XCTAssertEqual(try fixture.store.record(id: removal.id)?.state, .recoveryRequired, label)
            try fixture.assertHeld(held, in: relaunch.first, label)
            XCTAssertEqual(relaunch.firstOperations, [], label)
            relaunch.assertSecondLaunchChangesNothing()
            fixture.assertEdgesWereObserved()
        }
    }

    /// A transfer stopped in a copy phase is not resumed either, and one saved
    /// before `.DS_Store` exclusion is not migrated (migration rewrites its
    /// staging copy).
    func testLaunchDoesNotResumeANewerUnfinishedTransferWhileTheProjectsRemovalAwaitsReview() async throws {
        let unfinished: [(state: VaultTransferState, legacyMetadata: Bool)] = [
            (.copyingToArchiveStaging, false),
            (.awaitingProviderDurability, true),
        ]
        for (state, legacyMetadata) in unfinished {
            let label = legacyMetadata ? "\(state) with legacy Finder metadata" : "\(state)"
            let fixture = try TransferCrashFixture()
            defer { fixture.remove() }
            let removal = try await fixture.stoppedRemoval(in: .removingActiveCopy)
            var newer = try fixture.unfinishedRecord(
                in: state, projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(20)
            )
            if legacyMetadata { try fixture.addLegacyFinderMetadata(to: &newer) }
            let held = try fixture.saved(newer)

            let relaunch = try await fixture.launchTwice()

            XCTAssertEqual(try fixture.store.record(id: removal.id)?.state, .recoveryRequired, label)
            try fixture.assertHeld(held, in: relaunch.first, label)
            XCTAssertEqual(relaunch.firstOperations, [], label)
            relaunch.assertSecondLaunchChangesNothing()
            fixture.assertEdgesWereObserved()
        }
    }

    /// A removal the person has not recovered since an earlier launch holds its
    /// project the same way, and this launch saves nothing.
    func testLaunchHoldsARetryableTransferBehindARemovalReviewedAtAnEarlierLaunch() async throws {
        for origin in [VaultTransferState.removingActiveCopy, .evictingProviderCache] {
            let label = "\(origin)"
            let fixture = try TransferCrashFixture()
            defer { fixture.remove() }
            let removal = try await fixture.interruptedRemoval(origin: origin)
            let newer = try fixture.failedRecord(
                origin: .awaitingProviderDurability, retryCount: 1,
                projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(20)
            )
            let held = try fixture.saved(newer)
            let setupEdges = fixture.store.transferEdges.count

            let relaunch = try await fixture.launchTwice()

            XCTAssertEqual(try fixture.store.record(id: removal.id), removal, label)
            try fixture.assertHeld(held, in: relaunch.first, label)
            XCTAssertEqual(relaunch.firstOperations, [], label)
            XCTAssertEqual(fixture.store.transferEdges.count, setupEdges, "launch saved nothing (\(label))")
            relaunch.assertSecondLaunchChangesNothing()
            fixture.assertEdgesWereObserved()
        }
    }

    /// A hand-off whose save throws leaves the removal in its removal phase; the
    /// project waits all the same, and still waits once the next launch hands
    /// the removal to review.
    func testLaunchHoldsTheProjectWhenItsRemovalsReviewSaveFails() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let removal = try await fixture.stoppedRemoval(in: .removingActiveCopy)
        let newer = try fixture.failedRecord(
            origin: .awaitingProviderDurability, retryCount: 1,
            projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(20)
        )
        let held = try fixture.saved(newer)
        let savedRemoval = try fixture.store.record(id: removal.id)
        fixture.store.failNextSave(of: .recoveryRequired)
        let engine = try fixture.engine()
        fixture.files.reset()

        let failedSaveLaunch = await engine.recoverAtLaunch()

        XCTAssertEqual(try fixture.store.record(id: removal.id), savedRemoval)
        try fixture.assertHeld(held, in: failedSaveLaunch, "the launch whose save failed")
        XCTAssertEqual(fixture.files.operations, [])

        let nextLaunch = await engine.recoverAtLaunch()

        XCTAssertEqual(try fixture.store.record(id: removal.id)?.state, .recoveryRequired)
        try fixture.assertHeld(held, in: nextLaunch, "the next launch")
        XCTAssertEqual(fixture.files.operations, [])
        fixture.assertEdgesWereObserved()
    }

    /// When the removal is the project's newest record, an older incomplete
    /// record is the one launch would retry. It copies the same Active folder,
    /// so it waits too.
    func testLaunchHoldsAnOlderRetryableTransferOfTheProject() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let removal = try await fixture.stoppedRemoval(in: .removingActiveCopy)
        let older = try fixture.failedRecord(
            origin: .awaitingProviderDurability, retryCount: 1,
            projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(-20)
        )
        let held = try fixture.saved(older)

        let relaunch = try await fixture.launchTwice()

        XCTAssertEqual(try fixture.store.record(id: removal.id)?.state, .recoveryRequired)
        try fixture.assertHeld(held, in: relaunch.first, "older record")
        XCTAssertEqual(relaunch.firstOperations, [])
        relaunch.assertSecondLaunchChangesNothing()
        fixture.assertEdgesWereObserved()
    }

    /// The hold is per project: another song's retryable transfer in the same
    /// journal is retried as usual.
    func testLaunchRetriesAnotherProjectsTransferBesideAHeldProject() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let removal = try await fixture.stoppedRemoval(in: .removingActiveCopy)
        let newer = try fixture.failedRecord(
            origin: .awaitingProviderDurability, retryCount: 1,
            projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(20)
        )
        let held = try fixture.saved(newer)
        let other = try fixture.failedRecord(
            origin: .awaitingProviderDurability, retryCount: 1,
            source: fixture.otherSongSource(), createdAt: removal.createdAt.addingTimeInterval(30)
        )

        let relaunch = try await fixture.launchTwice()

        try fixture.assertHeld(held, in: relaunch.first, "held project")
        XCTAssertEqual(try fixture.store.record(id: other.id)?.state, .archiveVerified)
        XCTAssertEqual(relaunch.firstOperations, ["move \(other.destinationURL.lastPathComponent)"])
        relaunch.assertSecondLaunchChangesNothing()
        try fixture.assertOnlyGeneration(of: other)
        fixture.assertEdgesWereObserved()
    }

    /// Recover ends the hold by retiring what it held: each other incomplete
    /// transfer of the project goes to `superseded` by the recovered removal,
    /// before that is saved `archiveVerified`, with its staging kept. A late
    /// phase would otherwise promote staging copied from an incomplete folder,
    /// and a restore would use it. Another project keeps its transfer, and the
    /// next launch resumes nothing.
    func testRecoverRetiresTheTransfersItsRemovalHeld() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let removal = try await fixture.stoppedRemoval(in: .removingActiveCopy)
        let newerFailure = try fixture.failedRecord(
            origin: .awaitingProviderDurability, retryCount: 1,
            projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(20)
        )
        let newerUnfinished = try fixture.unfinishedRecord(
            in: .awaitingProviderDurability, projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(30)
        )
        let otherProject = try fixture.failedRecord(
            origin: .awaitingProviderDurability, retryCount: 5,
            source: fixture.otherSongSource(), createdAt: removal.createdAt.addingTimeInterval(40)
        )
        let held = [try fixture.saved(newerFailure), try fixture.saved(newerUnfinished)]
        let savedOther = try fixture.store.record(id: otherProject.id)
        let engine = try fixture.engine()
        _ = await engine.recoverAtLaunch()
        for saved in held { XCTAssertEqual(try fixture.store.record(id: saved.record.id), saved.record, "held before Recover") }

        let recovered = try await engine.recoverInterruptedRemoval(id: removal.id)

        XCTAssertEqual(recovered.state, .archiveVerified)
        for saved in held {
            let retired = try XCTUnwrap(fixture.store.record(id: saved.record.id))
            XCTAssertEqual(retired.state, .superseded)
            XCTAssertEqual(retired.supersededBy, removal.id)
            XCTAssertEqual(try fixture.snapshot(saved.record.stagingURL), saved.staging, "nothing deleted")
            XCTAssertFalse(FileManager.default.fileExists(atPath: saved.record.destinationURL.path))
        }
        XCTAssertEqual(try fixture.store.record(id: otherProject.id), savedOther)
        let journalAfterRecover = try fixture.store.allTransferRecords()
        fixture.files.reset()

        _ = await engine.recoverAtLaunch()

        XCTAssertEqual(fixture.files.operations, [], "the next launch resumes nothing")
        XCTAssertEqual(try fixture.store.allTransferRecords(), journalAfterRecover)
        fixture.assertEdgesWereObserved()
    }

    /// The person's Retry of a held transfer is refused, before and after
    /// launch hands the removal to review; the runtime reports `unavailable`.
    func testRetryIsRefusedWhileTheProjectsRemovalAwaitsReview() async throws {
        for handedToReview in [false, true] {
            let label = handedToReview ? "removal under review" : "removal not yet handed to review"
            let fixture = try TransferCrashFixture()
            defer { fixture.remove() }
            let removal = try await fixture.stoppedRemoval(in: .removingActiveCopy)
            let newer = try fixture.failedRecord(
                origin: .awaitingProviderDurability, retryCount: 5,
                projectID: removal.projectID, createdAt: removal.createdAt.addingTimeInterval(20)
            )
            let engine = try fixture.engine()
            if handedToReview { _ = await engine.recoverAtLaunch() }
            let held = try fixture.saved(newer)
            fixture.files.reset()

            let retried = await engine.retryRecoverableTransfer(id: newer.id)

            XCTAssertNil(retried, label)
            XCTAssertEqual(try fixture.store.record(id: newer.id), held.record, label)
            XCTAssertEqual(try fixture.snapshot(newer.stagingURL), held.staging, label)
            XCTAssertFalse(FileManager.default.fileExists(atPath: newer.destinationURL.path), label)
            XCTAssertEqual(fixture.files.operations, [], label)
            fixture.assertEdgesWereObserved()
        }
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

    // MARK: - Unlisted edges fail closed

    /// No transfer record ever held a restore-half state. A row in one fails
    /// at the phase switch, and the error path's edge into `failedRecoverable`
    /// is unlisted: the engine throws before it saves or touches a file, and
    /// the row stays as it was at every launch.
    func testAnUnlistedEdgeThrowsBeforeItSavesOrTouchesAFile() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        var foreign = try fixture.failedRecord(origin: .copyingToArchiveStaging, retryCount: 0, createdAt: Date())
        foreign.state = .materializingArchive
        foreign.error = nil
        try fixture.store.base.save(foreign)
        let saved = try XCTUnwrap(fixture.store.record(id: foreign.id))
        let staging = try fixture.snapshot(foreign.stagingURL)
        let original = try fixture.snapshot(fixture.source)

        let relaunch = try await fixture.launchTwice()

        XCTAssertEqual(relaunch.first, [saved])
        XCTAssertEqual(relaunch.firstOperations, [])
        relaunch.assertSecondLaunchChangesNothing()
        XCTAssertEqual(try fixture.store.record(id: foreign.id), saved)
        XCTAssertEqual(fixture.store.transferEdges, [])
        XCTAssertEqual(try fixture.snapshot(foreign.stagingURL), staging)
        XCTAssertEqual(try fixture.snapshot(fixture.source), original)
    }

    /// The save of `archiveVerified` fails. Its error path would save
    /// `archiveVerified → failedRecoverable`, an edge only a failed save
    /// reaches and the table does not list: the engine throws instead, the
    /// journal keeps the promotion phase, and launch finishes it without
    /// copying again.
    func testAFailedVerifiedSaveKeepsThePromotionPhaseForLaunch() async throws {
        let fixture = try TransferCrashFixture()
        defer { fixture.remove() }
        let original = try fixture.snapshot(fixture.source)
        fixture.store.failNextSave(of: .archiveVerified)

        do {
            _ = try await fixture.engine().archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("the failed save must stop the archive")
        } catch let error as VaultTransitionError {
            XCTAssertEqual(error, .illegal(from: .archiveVerified, to: .failedRecoverable))
        }

        let pending = try XCTUnwrap(fixture.store.recoverableRecords().first)
        XCTAssertEqual(pending.state, .promotingArchiveGeneration)
        XCTAssertEqual(pending.durability, .verifiedLocal)
        XCTAssertNil(pending.error)
        let relaunch = try await fixture.launchTwice()
        XCTAssertEqual(relaunch.first.map(\.state), [.archiveVerified])
        XCTAssertEqual(relaunch.firstOperations, [], "the promoted generation is verified, not copied again")
        relaunch.assertSecondLaunchChangesNothing()
        XCTAssertEqual(try fixture.snapshot(fixture.source), original)
        try fixture.assertOnlyGeneration(of: pending)
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

private struct SavedTransfer {
    let record: VaultTransferRecord
    let staging: [String: Data]
}

private final class TransferCrashFixture {
    let root: URL
    let active: URL
    let archive: URL
    let source: URL
    let databaseURL: URL
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
        databaseURL = root.appendingPathComponent("state/vault.sqlite")
        store = try VaultEdgeRecordingStore(databaseURL: databaseURL)
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

    /// A verified archive whose removal stopped in `origin`, already handed to
    /// review; saved past the recorder, since the test sets it up.
    func interruptedRemoval(origin: VaultTransferState = .removingActiveCopy) async throws -> VaultTransferRecord {
        var record = try await verifiedArchive()
        record.state = .recoveryRequired
        record.error = VaultTransferError(origin: origin, reason: .unknown, message: "Interrupted")
        try store.base.save(record)
        return record
    }

    /// A verified archive whose removal stopped in `phase` without a launch
    /// since; with `legacyFailure`, saved as the V1 `failedRecoverable` of that
    /// phase instead. Saved past the recorder, since the test sets it up.
    func stoppedRemoval(in phase: VaultTransferState, legacyFailure: Bool = false) async throws -> VaultTransferRecord {
        var record = try await verifiedArchive()
        record.state = legacyFailure ? .failedRecoverable : phase
        record.error = legacyFailure ? VaultTransferError(origin: phase, reason: .unknown, message: "stopped") : nil
        try store.base.save(record)
        return record
    }

    /// A failed transfer with a complete staging copy of `source` (the
    /// fixture's song by default), saved past the recorder.
    func failedRecord(
        origin: VaultTransferState,
        retryCount: Int,
        projectID: ProjectID = ProjectID(),
        source: URL? = nil,
        createdAt: Date
    ) throws -> VaultTransferRecord {
        let source = source ?? self.source
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

    /// A transfer stopped in `state` after its staging copy and manifest were
    /// saved, saved past the recorder.
    func unfinishedRecord(in state: VaultTransferState, projectID: ProjectID, createdAt: Date) throws -> VaultTransferRecord {
        var record = try failedRecord(origin: state, retryCount: 0, projectID: projectID, createdAt: createdAt)
        record.state = state
        record.error = nil
        try store.base.save(record)
        return record
    }

    /// Adds a Finder metadata file to `record`'s staging copy and manifest, as a
    /// transfer saved before `.DS_Store` exclusion holds them; saved past the
    /// recorder. Launch migrates such a record before it resumes it.
    func addLegacyFinderMetadata(to record: inout VaultTransferRecord) throws {
        let file = record.stagingURL.appendingPathComponent(".DS_Store")
        let data = Data("finder metadata".utf8)
        try data.write(to: file)
        let manifest = try XCTUnwrap(record.manifest)
        let legacy = VaultManifest(
            entries: manifest.entries + [.init(
                relativePath: ".DS_Store",
                type: .regularFile,
                byteCount: Int64(data.count),
                modifiedAt: try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast,
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            )],
            rootAllocatedByteCount: manifest.rootAllocatedByteCount,
            rootExtendedAttributeBytes: manifest.rootExtendedAttributeBytes
        )
        record.manifestID = legacy.id
        record.manifest = legacy
        try store.base.save(record)
    }

    /// A second song's Active folder.
    func otherSongSource() throws -> URL {
        let folder = active.appendingPathComponent("Other Song", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("other-project".utf8).write(to: folder.appendingPathComponent("Other Song.cpr"))
        return folder
    }

    /// `record` as the journal holds it, with its staging bytes.
    func saved(_ record: VaultTransferRecord) throws -> SavedTransfer {
        SavedTransfer(record: try XCTUnwrap(store.record(id: record.id)), staging: try snapshot(record.stagingURL))
    }

    /// Launch returned the record as saved and left its journal row and staging
    /// bytes as they were; it has no generation.
    func assertHeld(
        _ saved: SavedTransfer, in results: [VaultTransferRecord], _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(try store.record(id: saved.record.id), saved.record, "journal row (\(label))", file: file, line: line)
        XCTAssertEqual(try snapshot(saved.record.stagingURL), saved.staging, "staging bytes (\(label))", file: file, line: line)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: saved.record.destinationURL.path),
            "generation (\(label))", file: file, line: line
        )
        XCTAssertTrue(results.contains(saved.record), "returned as saved (\(label))", file: file, line: line)
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
