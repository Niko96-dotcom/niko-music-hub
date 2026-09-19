@testable import AppCore
import Darwin
import Foundation
import NikoMusicCore
import SQLite3
import XCTest

final class LiveProjectVaultRuntimeTests: XCTestCase {
    func testIdenticalSiblingProjectsArchiveIndependently() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: true)
        // Exercise a root alias with a different path length from the canonical
        // song URL, as /tmp and /private/tmp do in the actual macOS UI.
        let alias = fixture.root.appendingPathComponent("Active Folder Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.active)
        let activeID = fixture.activeID
        try fixture.settingsStore.updateSettings {
            $0.musicRoots.removeAll { $0.role == .active }
            $0.musicRoots.append(StoredMusicRoot(id: activeID, role: .active, url: alias))
        }
        let runtime = try fixture.runtime(projectOpener: RuntimeNoopVaultProjectOpener())
        let first = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
        XCTAssertEqual(first.record.locations.first?.relativePath, "Synthetic Song")
        let sibling = fixture.active.appendingPathComponent("Separate Song", isDirectory: true)
        try FileManager.default.copyItem(at: fixture.project, to: sibling)
        let file = sibling.appendingPathComponent("Synthetic Song.cpr")
        let version = ProjectVersion(filePath: file, fileName: file.lastPathComponent, modifiedAt: Date(timeIntervalSince1970: 1))
        let song = Song(folderPath: sibling, originalFolderName: "Separate Song", displayTitle: "Separate Song", projectVersions: [version], latestCPR: version)
        let archived = try await runtime.archive(song: song, trigger: .manual)
        XCTAssertNotEqual(archived.record.id, first.record.id)
        XCTAssertEqual(archived.transfer?.sourceURL.resolvingSymlinksInPath().path, sibling.resolvingSymlinksInPath().path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sibling.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertEqual(try fixture.transferStore().record(id: XCTUnwrap(first.transfer?.id))?.state, .archiveVerified)
        let restored = try await runtime.restoreAndOpen(snapshot: archived)
        XCTAssertEqual(restored.destinationURL.resolvingSymlinksInPath().path, sibling.resolvingSymlinksInPath().path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testChangingVaultRootCreatesGenerationInNewRootWithoutReusingOldTransfer() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: true)
        let runtime = try fixture.runtime(projectOpener: RuntimeNoopVaultProjectOpener())
        let first = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
        let nextRoot = fixture.root.appendingPathComponent("Replacement Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: nextRoot, withIntermediateDirectories: true)
        let stored = StoredMusicRoot(role: .archive, url: nextRoot)
        try fixture.settingsStore.updateSettings {
            $0.musicRoots.removeAll { $0.role == .archive }
            $0.musicRoots.append(stored)
            $0.vault.archiveRootID = stored.id
        }
        let next = try await runtime.archive(song: fixture.song, trigger: .manual)
        XCTAssertNotEqual(next.transfer?.id, first.transfer?.id)
        XCTAssertEqual(next.transfer?.state, .archivedLocal)
        XCTAssertTrue(try XCTUnwrap(next.transfer?.destinationURL).path.hasPrefix(nextRoot.path))
        XCTAssertEqual(try fixture.transferStore().record(id: XCTUnwrap(first.transfer?.id))?.state, .archiveVerified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(first.transfer?.destinationURL).path))
    }

    func testReviewedInterruptedRemovalRestoresWithoutOverwritingPartialActive() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: true)
        let runtime = try fixture.runtime(projectOpener: RuntimeNoopVaultProjectOpener())
        let before = try VaultManifestBuilder().build(at: fixture.project)
        let snapshot = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
        var record = try XCTUnwrap(snapshot.transfer)
        record.state = .recoveryRequired
        record.error = .init(origin: .removingActiveCopy, reason: .unknown, message: "Interrupted")
        try fixture.transferStore().save(record)
        let projectFile = try XCTUnwrap(before.entries.first { $0.relativePath.hasSuffix(".cpr") })
        try Data("surviving partial contents".utf8).write(to: fixture.project.appendingPathComponent(projectFile.relativePath))
        let restored = try await runtime.recoverInterruptedArchive(snapshot: snapshot)
        XCTAssertNotNil(restored.completedAt)
        try VaultManifestBuilder().verify(before, at: restored.destinationURL)
        let preserved = try XCTUnwrap(try fixture.transferStore().record(id: record.id)?.preservedActiveCopies?.last)
        XCTAssertEqual(try Data(contentsOf: preserved.appendingPathComponent(projectFile.relativePath)), Data("surviving partial contents".utf8))
    }

    func testInterruptedRemovalRecoveryReportsUncertainActivityAsUncertainty() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: true)
        let runtime = try fixture.runtime(
            activityProbe: UncertainActivityProbe(reason: "activity probe timed out"),
            projectOpener: RuntimeNoopVaultProjectOpener()
        )
        let before = try VaultManifestBuilder().build(at: fixture.project)
        let snapshot = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
        var record = try XCTUnwrap(snapshot.transfer)
        record.state = .recoveryRequired
        record.error = .init(origin: .removingActiveCopy, reason: .unknown, message: "Interrupted")
        try fixture.transferStore().save(record)

        do {
            _ = try await runtime.recoverInterruptedArchive(snapshot: snapshot)
            XCTFail("expected an uncertain activity probe to postpone recovery")
        } catch {
            // The DAW was never observed running; the message must say the check
            // was inconclusive rather than tell the user to close Cubase.
            XCTAssertEqual(
                error as? ProjectVaultRuntimeError,
                .activityPostponed(.uncertainActivity("activity probe timed out"))
            )
        }
        try VaultManifestBuilder().verify(before, at: fixture.project)
        XCTAssertEqual(try fixture.transferStore().record(id: record.id)?.state, .recoveryRequired)
    }

    func testExplicitRetryProjectsVerifiedTransferOntoCurrentCatalogEntry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let failed = try fixture.failedDurabilityRecord()
        try fixture.transferStore().save(failed)
        try fixture.saveCatalogEntry(projectID: failed.projectID)
        let runtime = try fixture.runtime()
        // The browser hands back whatever it last cached; that record may be stale.
        let stale = ProjectVaultRuntimeSnapshot(
            record: ProjectRecord(id: failed.projectID, canonicalTitle: "Stale Title", locations: []),
            transfer: failed
        )

        let retried = try await runtime.retry(snapshot: stale)

        XCTAssertEqual(retried.transfer?.state, .archiveVerified)
        XCTAssertEqual(retried.record.canonicalTitle, "Synthetic Song")
        XCTAssertEqual(retried.record.latestManifestID, retried.transfer?.manifestID)
        XCTAssertEqual(retried.record.lastVerifiedAt, retried.transfer?.updatedAt)
        XCTAssertTrue(retried.record.locations.contains { $0.kind == .active && $0.rootID == fixture.activeID })
        XCTAssertTrue(retried.record.locations.contains { $0.kind == .archive && $0.rootID == fixture.archiveID })
        // `ProjectLocation` stamps `lastSeenAt` per construction, so compare the
        // fields the browser renders rather than whole-record equality.
        let snapshots = try await runtime.snapshots()
        let listed = try XCTUnwrap(snapshots.first { $0.record.id == failed.projectID })
        XCTAssertEqual(listed.record.canonicalTitle, retried.record.canonicalTitle)
        XCTAssertEqual(listed.record.latestManifestID, retried.record.latestManifestID)
        XCTAssertEqual(listed.record.lastVerifiedAt, retried.record.lastVerifiedAt)
        XCTAssertEqual(
            listed.record.locations.map { "\($0.kind.rawValue):\($0.rootID):\($0.relativePath):\($0.availability)" },
            retried.record.locations.map { "\($0.kind.rawValue):\($0.rootID):\($0.relativePath):\($0.availability)" },
            "retry must return what snapshots() reports"
        )
    }

    func testSnapshotPinnedHonorsEveryKeepLocalKeyTheRuntimeEnforces() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: true)
        let runtime = try fixture.runtime()
        let archived = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
        let transfer = try XCTUnwrap(archived.transfer)
        let keys: [(String, String)] = [
            ("song ID", fixture.song.id),
            ("transfer source path", transfer.sourceURL.path),
            ("project ID", archived.record.id.description),
            ("resolved source path", transfer.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path),
        ]
        for (label, key) in keys {
            try fixture.settingsStore.updateSettings { $0.vault.keepLocalProjectIDs = [key] }
            let snapshot = try await runtime.snapshots().first { $0.record.id == archived.record.id }
            XCTAssertEqual(snapshot?.record.pinned, true, "Keep Local stored by \(label) must show as pinned")
        }
        try fixture.settingsStore.updateSettings { $0.vault.keepLocalProjectIDs = ["/nowhere/Other Song"] }
        let unpinned = try await runtime.snapshots().first { $0.record.id == archived.record.id }
        XCTAssertEqual(unpinned?.record.pinned, false)

        // Without any transfer the browser keys Keep Local by song ID; the catalog's
        // Active location is enough to recognise it.
        let pinnedID = ProjectID()
        let songID = fixture.song.id
        try fixture.saveCatalogEntry(projectID: pinnedID)
        try fixture.settingsStore.updateSettings { $0.vault.keepLocalProjectIDs = [songID] }
        let byLocation = try await runtime.snapshots().first { $0.record.id == pinnedID }
        XCTAssertNil(byLocation?.transfer)
        XCTAssertEqual(byLocation?.record.pinned, true)
    }

    func testManualArchiveRemovesActiveAndCanRearchiveRestoredGeneration() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: true)
        try fixture.settingsStore.updateSettings { $0.vault.automaticArchiving = false }
        let runtime = try fixture.runtime(projectOpener: RuntimeNoopVaultProjectOpener())
        let before = try VaultManifestBuilder().build(at: fixture.project)
        let copy = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))

        let archived = try await runtime.archive(song: fixture.song, trigger: .manual)
        XCTAssertEqual(archived.transfer?.id, copy.transfer?.id)
        XCTAssertEqual(archived.transfer?.state, .archivedLocal)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertEqual(ProjectVaultCardPresentation(record: archived.record, transferState: archived.transfer?.state).state, .archived)

        let restored = try await runtime.restoreAndOpen(snapshot: archived)
        XCTAssertNotNil(restored.completedAt)
        try VaultManifestBuilder().verify(before, at: fixture.project)
        let again = try await runtime.archive(song: fixture.song, trigger: .manual)
        XCTAssertEqual(again.transfer?.id, copy.transfer?.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))
        try VaultManifestBuilder().verify(before, at: try XCTUnwrap(again.transfer?.destinationURL))
        XCTAssertEqual(try fixture.transferStore().allTransferRecords().count, 1)
    }

    func testManualArchiveCreatesNewGenerationAndRequiresRemovalSafety() async throws {
        for blocker in ["none", "backup", "keepLocal", "emergency", "daw", "openFiles"] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            try fixture.saveSettings(stage: .privateBeta, backupConfirmed: blocker != "backup", emergencyStop: blocker == "emergency")
            if blocker == "keepLocal" {
                let projectPath = fixture.project.path
                try fixture.settingsStore.updateSettings { $0.vault.keepLocalProjectIDs.insert(projectPath) }
            }
            let runtime = try fixture.runtime(activityProbe: ManualArchiveProbe(blocker: blocker))
            do {
                let archived = try await runtime.archive(song: fixture.song, trigger: .manual)
                XCTAssertEqual(blocker, "none")
                XCTAssertEqual(archived.transfer?.state, .archivedLocal)
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))
            } catch let error as ProjectVaultRuntimeError {
                let expected: ProjectVaultRuntimeError = switch blocker {
                case "backup": .independentBackupRequired
                case "keepLocal": .keepLocal
                case "emergency": .emergencyStop
                case "daw": .activityPostponed(.cubaseRunning)
                case "openFiles": .activityPostponed(.openFiles)
                default: .unavailable
                }
                XCTAssertEqual(error, expected, blocker)
                XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
                XCTAssertEqual(try fixture.transferStore().allTransferRecords().first?.state, .archiveVerified)
            }
        }
    }

    func testOlderRetryCannotWakeRecoveryWhenSelectedTransferIsExhaustedOrDeferred() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false, emergencyStop: false)
        let store = try fixture.transferStore()
        let older = try fixture.failedDurabilityRecord(retryCount: 3)
        try store.save(older)
        var selected = VaultTransferRecord(
            projectID: older.projectID,
            sourceURL: older.sourceURL,
            stagingURL: older.stagingURL,
            destinationURL: older.destinationURL,
            state: .failedRecoverable,
            createdAt: older.updatedAt.addingTimeInterval(1)
        )
        selected.error = older.error
        selected.retryCount = 7
        try store.save(selected)
        let runtime = try fixture.runtime()

        for _ in 0..<2 {
            let deadline = try await runtime.nextAutomaticRecoveryDate()
            XCTAssertNil(deadline, "an older eligible retry cannot wake a skipped recovery")
            await runtime.recoverAtLaunch()
            XCTAssertEqual(try store.record(id: older.id), older)
            XCTAssertEqual(try store.record(id: selected.id), selected)
        }

        let future = Date().addingTimeInterval(3600)
        selected.retryCount = 2
        selected.nextRetryAt = future
        try store.save(selected)
        let deferredDeadline = try await runtime.nextAutomaticRecoveryDate()
        XCTAssertEqual(deferredDeadline, future, "only the selected transfer sets the deadline")

        // Another song's eligible retry must remain schedulable.
        var otherSong = try fixture.failedDurabilityRecord()
        otherSong.nextRetryAt = future.addingTimeInterval(-100)
        try store.save(otherSong)
        let otherDeadline = try await runtime.nextAutomaticRecoveryDate()
        XCTAssertEqual(otherDeadline, otherSong.nextRetryAt)
    }

    func testAutomaticRecoveryDeadlineHonorsBackoffBudgetAndSafetyGates() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false, emergencyStop: false)
        let store = try fixture.transferStore()
        var record = try fixture.failedDurabilityRecord()
        let due = Date().addingTimeInterval(3600)
        record.nextRetryAt = due
        try store.save(record)
        let runtime = try fixture.runtime()
        var next = try await runtime.nextAutomaticRecoveryDate()
        XCTAssertEqual(next, due)
        await runtime.recoverAtLaunch()
        XCTAssertEqual(try store.record(id: record.id)?.state, .failedRecoverable)

        record.retryCount = VaultTransferRecoveryPolicy.production.maximumAutomaticAttempts
        try store.save(record)
        next = try await runtime.nextAutomaticRecoveryDate()
        XCTAssertNil(next)

        record.retryCount = 1
        record.error = VaultTransferError(origin: .removingActiveCopy, reason: .unknown, message: "review")
        try store.save(record)
        next = try await runtime.nextAutomaticRecoveryDate()
        XCTAssertNil(next)

        record.error = VaultTransferError(origin: .awaitingProviderDurability, reason: .providerUnsynced, message: "pending")
        try store.save(record)
        try fixture.settingsStore.updateSettings { $0.vault.automationEmergencyStop = true }
        next = try await runtime.nextAutomaticRecoveryDate()
        XCTAssertNil(next)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.stagingURL.path))
    }

    func testMutationFileLeaseReportsAccessFailuresWithoutClaimingContention() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-lock-errors-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let lock = root.appendingPathComponent("lease")
        XCTAssertThrowsError(try ProjectVaultMutationFileLease(url: lock)) { error in
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .mutationLockUnavailable(ENOENT))
        }
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ProjectVaultMutationFileLease(url: lock)) { error in
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .mutationLockUnavailable(EISDIR))
        }
        try FileManager.default.removeItem(at: lock)
        try Data().write(to: lock)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: lock.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lock.path) }
        XCTAssertThrowsError(try ProjectVaultMutationFileLease(url: lock)) { error in
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .mutationLockUnavailable(EACCES))
        }
    }

    func testMutationFileLeaseIsNonblockingAcrossProcessesAndAutoReleasesOnExit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-vault-cross-process-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let leaseURL = root.appendingPathComponent("archive-index.sqlite.project-vault.lock")
        let childInput = Pipe()
        let childOutput = Pipe()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [
            "-e",
            "use Fcntl qw(:flock); open(my $fh, '>>', $ARGV[0]) or die $!; flock($fh, LOCK_EX | LOCK_NB) or die $!; select(STDOUT); $| = 1; print qq(LOCKED\\n); <STDIN>;",
            leaseURL.path,
        ]
        child.standardInput = childInput
        child.standardOutput = childOutput
        child.standardError = childOutput
        try child.run()
        defer {
            if child.isRunning {
                child.terminate()
                child.waitUntilExit()
            }
        }

        var acknowledgement = Data()
        while acknowledgement.last != UInt8(ascii: "\n") {
            acknowledgement.append(try XCTUnwrap(
                childOutput.fileHandleForReading.read(upToCount: 1)
            ))
        }
        XCTAssertEqual(String(decoding: acknowledgement, as: UTF8.self), "LOCKED\n")
        XCTAssertThrowsError(try ProjectVaultMutationFileLease(url: leaseURL)) { error in
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .mutationInProgress)
        }

        childInput.fileHandleForWriting.write(Data("release\n".utf8))
        childInput.fileHandleForWriting.closeFile()
        child.waitUntilExit()
        XCTAssertEqual(child.terminationStatus, 0)

        let recoveredLease = try ProjectVaultMutationFileLease(url: leaseURL)
        recoveredLease.release()
    }

    func testFoundationCapacityProbeResolvesSourceAndTargetSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-capacity-symlink-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let realSource = root.appendingPathComponent("Real Source")
        let realTarget = root.appendingPathComponent("Real Target")
        let sourceLink = root.appendingPathComponent("Source Link")
        let targetLink = root.appendingPathComponent("Target Link")
        try FileManager.default.createDirectory(at: realSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: realTarget, withIntermediateDirectories: true)
        try Data([1]).write(to: realSource.appendingPathComponent("tiny.cpr"))
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: realSource)
        try FileManager.default.createSymbolicLink(at: targetLink, withDestinationURL: realTarget)
        let recorder = CapacityLookupRecorder()
        let probe = FoundationProjectVaultCapacityProbe(
            capacityLookup: { url in recorder.recordCapacity(url); return 500 * 1_073_741_824 },
            blockSizeLookup: { url in recorder.recordBlockSize(url); return 4_096 }
        )

        _ = try probe.writeSnapshot(sourceURL: sourceLink, targetRootURL: targetLink)

        XCTAssertEqual(recorder.capacityURLs, [realTarget.standardizedFileURL.path])
        XCTAssertEqual(recorder.blockSizeURLs, [realTarget.standardizedFileURL.path])
    }

    func testFoundationCapacityProbeUsesOrdinaryAvailableCapacity() throws {
        let root = FileManager.default.temporaryDirectory
        let ordinaryAvailableCapacity = try XCTUnwrap(
            root.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
        )
        let probe = FoundationProjectVaultCapacityProbe(
            capacityLookup: { _ in Int64(ordinaryAvailableCapacity) },
            blockSizeLookup: { _ in 4_096 }
        )

        let actual = try probe.availableCapacityBytes(at: root)

        XCTAssertEqual(actual, Int64(ordinaryAvailableCapacity))
    }

    func testFoundationCapacityProbeRoundsTinyFilesToDestinationAllocationBlocks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-capacity-tiny-\(UUID().uuidString)")
        let source = root.appendingPathComponent("Source")
        let target = root.appendingPathComponent("Target")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for index in 0..<1_000 {
            try Data([UInt8(index % 251)]).write(to: source.appendingPathComponent("tiny-\(index)"))
        }
        let probe = FoundationProjectVaultCapacityProbe(
            capacityLookup: { _ in 500 * 1_073_741_824 },
            blockSizeLookup: { _ in 4_096 }
        )

        let snapshot = try probe.writeSnapshot(sourceURL: source, targetRootURL: target)

        let entryAllocation = Int64(1_001 * 4_096)
        let fixedReserve = Int64(64 * 1_024 * 1_024)
        XCTAssertGreaterThanOrEqual(snapshot.projectedCopyBytes, entryAllocation + fixedReserve)
    }

    func testFoundationCapacityProbeIncludesLargeExtendedAttributes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-capacity-xattr-\(UUID().uuidString)")
        let source = root.appendingPathComponent("Source")
        let target = root.appendingPathComponent("Target")
        let file = source.appendingPathComponent("project.cpr")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data([1]).write(to: file)
        let probe = FoundationProjectVaultCapacityProbe()
        let before = try probe.writeSnapshot(sourceURL: source, targetRootURL: target).projectedCopyBytes
        let xattr = [UInt8](repeating: 7, count: 64 * 1_024)
        let result = file.withUnsafeFileSystemRepresentation { path in
            xattr.withUnsafeBytes { bytes in
                setxattr(path, "com.niko.capacity-test", bytes.baseAddress, bytes.count, 0, 0)
            }
        }
        XCTAssertEqual(result, 0)

        let after = try probe.writeSnapshot(sourceURL: source, targetRootURL: target).projectedCopyBytes

        XCTAssertGreaterThanOrEqual(after - before, 64 * 1_024)
    }

    func testFoundationManifestProjectionUsesPersistedAllocationAndXattrsPerEntry() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-manifest-projection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let probe = FoundationProjectVaultCapacityProbe(
            capacityLookup: { _ in 1_000_000_000 },
            blockSizeLookup: { _ in 4_096 }
        )
        let manifest = VaultManifest(entries: [
            .init(relativePath: "Audio", type: .directory, byteCount: 0, modifiedAt: .distantPast, sha256: nil, allocatedByteCount: 0, extendedAttributeBytes: 0),
            .init(relativePath: "Audio/a.wav", type: .regularFile, byteCount: 1, modifiedAt: .distantPast, sha256: "a", allocatedByteCount: 4_096, extendedAttributeBytes: 65_536),
            .init(relativePath: "Audio/b.wav", type: .regularFile, byteCount: 4_097, modifiedAt: .distantPast, sha256: "b", allocatedByteCount: 8_192, extendedAttributeBytes: 17),
        ], rootAllocatedByteCount: 0, rootExtendedAttributeBytes: 0)

        let projected = try probe.conservativeProjectedBytes(
            manifest: manifest,
            targetRootURL: root
        )

        let rootAndEntries: Int64 = 4_096 + 4_096 + 69_632 + 12_288
        XCTAssertEqual(projected, 64 * 1_024 * 1_024 + rootAndEntries)
    }

    func testFoundationManifestProjectionRoundsManyTinyAllocatedFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-manifest-tiny-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let probe = FoundationProjectVaultCapacityProbe(
            capacityLookup: { _ in 1_000_000_000 },
            blockSizeLookup: { _ in 4_096 }
        )
        let entries = (0..<1_000).map { index in
            VaultManifest.Entry(
                relativePath: "tiny-\(index)",
                type: .regularFile,
                byteCount: 1,
                modifiedAt: .distantPast,
                sha256: "\(index)",
                allocatedByteCount: 4_096,
                extendedAttributeBytes: 0
            )
        }

        let projected = try probe.conservativeProjectedBytes(
            manifest: VaultManifest(
                entries: entries,
                rootAllocatedByteCount: 0,
                rootExtendedAttributeBytes: 0
            ),
            targetRootURL: root
        )

        XCTAssertEqual(projected, 64 * 1_024 * 1_024 + 1_001 * 4_096)
    }

    func testFoundationManifestProjectionFailsClosedForLegacyMissingAllocationMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-manifest-legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let probe = FoundationProjectVaultCapacityProbe(
            capacityLookup: { _ in 1_000_000_000 },
            blockSizeLookup: { _ in 4_096 }
        )
        let legacy = VaultManifest(entries: [
            .init(relativePath: "project.cpr", type: .regularFile, byteCount: 1, modifiedAt: .distantPast, sha256: "a"),
        ])

        XCTAssertThrowsError(
            try probe.conservativeProjectedBytes(manifest: legacy, targetRootURL: root)
        ) { error in
            XCTAssertEqual(error as? ProjectVaultCapacityProbeError, .invalidSize)
        }
    }

    func testNoLegacyPathUsesLogicalSizeFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-no-legacy-logical-fallback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let probe = FoundationProjectVaultCapacityProbe(
            capacityLookup: { _ in 1_000_000_000 },
            blockSizeLookup: { _ in 4_096 }
        )
        let legacy = VaultManifest(entries: [
            .init(
                relativePath: "project.cpr",
                type: .regularFile,
                byteCount: 42,
                modifiedAt: .distantPast,
                sha256: "legacy"
            ),
        ])

        XCTAssertGreaterThan(try legacy.validatedTotalBytes(), 0)
        XCTAssertThrowsError(
            try probe.conservativeProjectedBytes(
                manifest: legacy,
                projectionSupplement: nil,
                targetRootURL: root
            )
        ) { error in
            XCTAssertEqual(
                error as? ProjectVaultCapacityProbeError,
                .projectionEvidenceUnavailable,
                "logical byteCount must never substitute for allocation/xattr evidence"
            )
        }
    }

    func testBuiltManifestProjectionMatchesLiveTreeForMoreThan1024LargeXattrs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-manifest-xattr-scale-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let target = root.appendingPathComponent("Target", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let xattr = [UInt8](repeating: 7, count: 64 * 1_024)
        for index in 0..<1_100 {
            let file = source.appendingPathComponent("tiny-\(index)")
            try Data([UInt8(index % 251)]).write(to: file)
            let result = file.withUnsafeFileSystemRepresentation { path in
                xattr.withUnsafeBytes { bytes in
                    setxattr(path, "com.niko.capacity-test", bytes.baseAddress, bytes.count, 0, 0)
                }
            }
            XCTAssertEqual(result, 0)
        }
        let probe = FoundationProjectVaultCapacityProbe()
        let live = try probe.writeSnapshot(sourceURL: source, targetRootURL: target).projectedCopyBytes
        let manifest = try VaultManifestBuilder().build(at: source)
        let persisted = try probe.conservativeProjectedBytes(manifest: manifest, targetRootURL: target)

        XCTAssertEqual(persisted, live)
    }

    func testFoundationManifestProjectionFailsClosedOnOverflow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-manifest-overflow-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let probe = FoundationProjectVaultCapacityProbe(
            capacityLookup: { _ in Int64.max },
            blockSizeLookup: { _ in 4_096 }
        )
        let manifest = VaultManifest(entries: [
            .init(relativePath: "a", type: .regularFile, byteCount: Int64.max, modifiedAt: .distantPast, sha256: "a", allocatedByteCount: Int64.max, extendedAttributeBytes: 1),
        ], rootAllocatedByteCount: 0, rootExtendedAttributeBytes: 0)

        XCTAssertThrowsError(
            try probe.conservativeProjectedBytes(manifest: manifest, targetRootURL: root)
        ) { error in
            XCTAssertEqual(error as? ProjectVaultCapacityProbeError, .invalidSize)
        }
    }

    func testConcurrentRuntimeArchivesUseOneMutationLeaseAndOneTransfer() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let provider = BlockingRuntimeDurabilityProvider()
        let runtime = try fixture.runtime(archiveProviderFactory: { _ in provider })
        let song = fixture.song

        let first = Task {
            try await runtime.archive(song: song, trigger: .backupCopy)
        }
        await provider.waitUntilFirstBarrier()
        let second = Task { () -> Bool in
            do {
                _ = try await runtime.archive(song: song, trigger: .backupCopy)
                return false
            } catch {
                return true
            }
        }
        await Task.yield()
        await provider.releaseBarriers()

        _ = try await first.value
        let secondWasBlocked = await second.value
        let barrierCount = await provider.firstBarrierCount()
        XCTAssertTrue(secondWasBlocked, "the overlapping mutation must fail closed")
        XCTAssertEqual(barrierCount, 2)
        XCTAssertEqual(try fixture.transferStore().allTransferRecords().count, 1)
    }

    func testPersistedFailedTransferOwnsProjectAndBlocksFreshDoneTransfer() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let failed = try fixture.failedDurabilityRecord()
        try fixture.transferStore().save(failed)
        try fixture.saveCatalogEntry(projectID: failed.projectID)
        let runtime = try fixture.runtime()
        let before = try await runtime.snapshots()
        XCTAssertEqual(before.first?.record.id, failed.projectID)
        XCTAssertEqual(before.first?.transfer?.id, failed.id)

        var caughtError: ProjectVaultRuntimeError?
        do {
            _ = try await runtime.archive(song: fixture.song, trigger: .workflowDone)
            XCTFail("expected the persisted failed transfer to retain ownership")
        } catch {
            caughtError = error as? ProjectVaultRuntimeError
        }

        XCTAssertEqual(caughtError, .transferOwned)
        let records = try fixture.transferStore().allTransferRecords()
        XCTAssertEqual(records.map(\.id), [failed.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.destinationURL.path))
    }

    func testConcurrentRuntimeRecoveryUsesOneLeaseAndOneProviderAttempt() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let failed = try fixture.failedDurabilityRecord()
        try fixture.transferStore().save(failed)
        let provider = BlockingRuntimeDurabilityProvider(failsAtBarrier: true)
        let runtime = try fixture.runtime(
            archiveProviderFactory: { _ in provider },
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let first = Task { await runtime.recoverAtLaunch() }
        await provider.waitUntilFirstBarrier()
        let secondEntered = ThreadSafeFlag()
        let secondFinished = ThreadSafeFlag()
        let second = Task {
            secondEntered.set()
            await runtime.recoverAtLaunch()
            secondFinished.set()
        }
        for _ in 0..<100 where !secondEntered.value {
            try await Task.sleep(for: .milliseconds(5))
        }
        for _ in 0..<100 where !secondFinished.value {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(secondEntered.value)
        XCTAssertFalse(
            secondFinished.value,
            "a concurrent launch caller must join the blocked recovery instead of returning early"
        )
        await provider.releaseBarriers()
        await first.value
        await second.value

        let barrierCount = await provider.firstBarrierCount()
        let persisted = try XCTUnwrap(fixture.transferStore().record(id: failed.id))
        XCTAssertEqual(barrierCount, 1)
        XCTAssertEqual(persisted.retryCount, failed.retryCount + 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.destinationURL.path))
    }

    func testTwoRuntimeInstancesSerializeDifferentProjectsBeforeSecondCapacityLookup() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let secondSong = try fixture.makeAdditionalSong(named: "Second Project")
        let capacity = BlockingCapacityProbe(snapshot: .safe)
        let firstRuntime = try fixture.runtime(capacityProbe: capacity)
        let secondRuntime = try fixture.runtime(capacityProbe: capacity)
        let secondFinished = ThreadSafeFlag()
        let firstSong = fixture.song

        let first = Task { try await firstRuntime.archive(song: firstSong, trigger: .workflowDone) }
        await capacity.waitUntilFirstLookup()
        let second = Task { () -> Bool in
            defer { secondFinished.set() }
            do {
                _ = try await secondRuntime.archive(song: secondSong, trigger: .workflowDone)
                return false
            } catch {
                return error as? ProjectVaultRuntimeError == .mutationInProgress
            }
        }
        for _ in 0..<100 where capacity.callCount < 2 && !secondFinished.value {
            try await Task.sleep(for: .milliseconds(5))
        }
        let lookupsBeforeRelease = capacity.callCount
        capacity.release()

        _ = try await first.value
        let secondWasRejected = await second.value
        XCTAssertEqual(lookupsBeforeRelease, 1, "the shared lease must reject before a second capacity lookup")
        XCTAssertTrue(secondWasRejected)
        XCTAssertEqual(try fixture.transferStore().allTransferRecords().count, 1)
    }

    func testTwoRuntimeInstancesAtomicallyClaimSameCanonicalSource() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let capacity = BlockingCapacityProbe(snapshot: .safe)
        let firstRuntime = try fixture.runtime(capacityProbe: capacity)
        let secondRuntime = try fixture.runtime(capacityProbe: capacity)
        let secondFinished = ThreadSafeFlag()
        let song = fixture.song

        let first = Task { try await firstRuntime.archive(song: song, trigger: .workflowDone) }
        await capacity.waitUntilFirstLookup()
        let second = Task { () -> Bool in
            defer { secondFinished.set() }
            do {
                _ = try await secondRuntime.archive(song: song, trigger: .workflowDone)
                return false
            } catch {
                return error as? ProjectVaultRuntimeError == .mutationInProgress
            }
        }
        for _ in 0..<100 where capacity.callCount < 2 && !secondFinished.value {
            try await Task.sleep(for: .milliseconds(5))
        }
        capacity.release()

        _ = try await first.value
        let secondWasRejected = await second.value
        XCTAssertTrue(secondWasRejected)
        XCTAssertEqual(try fixture.transferStore().allTransferRecords().count, 1)
    }

    func testSnapshotsDuringRestoreDoNotRewriteCatalogOutsideMutationLease() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .friends, backupConfirmed: true)
        let archived = try await fixture.runtime().archive(song: fixture.song, trigger: .workflowDone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))

        var entries = try fixture.catalogStore().loadEntries()
        let projectID = try XCTUnwrap(archived.transfer?.projectID)
        let entryIndex = try XCTUnwrap(entries.firstIndex { $0.record.id == projectID })
        let locationIndex = try XCTUnwrap(entries[entryIndex].record.locations.firstIndex { $0.kind == .active })
        entries[entryIndex].record.locations[locationIndex].availability = .local
        try fixture.catalogStore().apply(ProjectCatalogReconciliation(
            entries: entries,
            reviews: try fixture.catalogStore().loadReviews(),
            metadataMigrations: [:]
        ))

        let provider = BlockingMaterializeProvider()
        let runtime = try fixture.runtime(archiveProviderFactory: { _ in provider })
        let restore = Task { try await runtime.restoreAndOpen(snapshot: archived) }
        await provider.waitUntilMaterialize()
        do {
            _ = try await runtime.snapshots()
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .mutationInProgress)
        }
        let persistedDuringRestore = try fixture.catalogStore().loadEntries()
        let availability = persistedDuringRestore
            .first { $0.record.id == projectID }?
            .record.locations.first { $0.kind == .active }?
            .availability
        await provider.release()
        _ = try await restore.value

        XCTAssertEqual(availability, .local, "snapshots must be read-only or fail busy while restore owns the mutation lease")
    }

    func testDoneCopiesAndVerifiesBelowPressureThresholdWithRoomForTransferReserve() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let settings = try fixture.settingsStore.loadSettings()
        XCTAssertEqual(settings.vault.minimumFreeSpaceGiB, 120)
        XCTAssertEqual(settings.vault.transferFreeSpaceReserveGiB, 5)
        let gib: Int64 = 1_073_741_824
        let runtime = try fixture.runtime(capacity: ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: 117 * gib,
            archiveAvailableCapacityBytes: 117 * gib,
            projectedArchiveBytes: 4 * gib
        ))
        let before = try VaultManifestBuilder().build(at: fixture.project)
        let result = try await runtime.archive(song: fixture.song, trigger: .workflowDone)
        let transfer = try XCTUnwrap(result.transfer)
        XCTAssertEqual(transfer.state, .archiveVerified)
        let manifest = try XCTUnwrap(transfer.manifest)
        try VaultManifestBuilder().verify(manifest, at: transfer.destinationURL)
        try VaultManifestBuilder().verify(before, at: fixture.project)
    }

    func testDoneCanRetryExistingCatalogEntryAfterCapacityPostponement() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let gib: Int64 = 1_073_741_824
        let blocked = try fixture.runtime(capacity: ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: 7 * gib,
            archiveAvailableCapacityBytes: 7 * gib,
            projectedArchiveBytes: 4 * gib
        ))
        do {
            _ = try await blocked.archive(song: fixture.song, trigger: .workflowDone)
            XCTFail("expected capacity postponement")
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .activityPostponed(.insufficientArchiveCapacity))
        }
        let prior = try XCTUnwrap(fixture.catalogStore().loadEntries().first)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
        let ready = try fixture.runtime(capacity: ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: 117 * gib,
            archiveAvailableCapacityBytes: 117 * gib,
            projectedArchiveBytes: 4 * gib
        ))
        let result = try await ready.archive(song: fixture.song, trigger: .workflowDone)
        let transfer = try XCTUnwrap(result.transfer)
        XCTAssertEqual(transfer.state, .archiveVerified)
        XCTAssertEqual(transfer.projectID, prior.record.id)
        XCTAssertEqual(try fixture.catalogStore().loadEntries().count, 1)
        try VaultManifestBuilder().verify(try XCTUnwrap(transfer.manifest), at: transfer.destinationURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testDoneUsesProjectedHeadroomBeforeCreatingTransfer() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(
            stage: .privateBeta,
            backupConfirmed: false,
            transferFreeSpaceReserveGiB: 60
        )
        let bytesPerGiB: Int64 = 1_073_741_824
        let runtime = try fixture.runtime(capacity: ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: 80 * bytesPerGiB,
            archiveAvailableCapacityBytes: 80 * bytesPerGiB,
            projectedArchiveBytes: 21 * bytesPerGiB
        ))

        do {
            _ = try await runtime.archive(song: fixture.song, trigger: .workflowDone)
            XCTFail("expected projected headroom postponement")
        } catch {
            XCTAssertEqual(
                error as? ProjectVaultRuntimeError,
                .activityPostponed(.insufficientArchiveCapacity)
            )
        }

        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.archive.path).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testDynamicArchiveAdmissionReloadsLatestSettingsFloorAfterProviderPrepare() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(
            stage: .privateBeta,
            backupConfirmed: false,
            transferFreeSpaceReserveGiB: 1
        )
        let settingsStore = fixture.settingsStore
        let provider = SettingsFloorRaisingProvider {
            try settingsStore.updateSettings {
                $0.vault.transferFreeSpaceReserveGiB = 80
            }
        }
        let bytesPerGiB: Int64 = 1_073_741_824
        let runtime = try fixture.runtime(
            capacity: ProjectVaultCapacitySnapshot(
                activeAvailableCapacityBytes: 80 * bytesPerGiB,
                archiveAvailableCapacityBytes: 80 * bytesPerGiB,
                projectedArchiveBytes: bytesPerGiB
            ),
            archiveProviderFactory: { _ in provider }
        )

        do {
            _ = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
            XCTFail("expected the freshly raised floor to deny the bulk copy")
        } catch {
            XCTAssertEqual(
                error as? VaultWriteAdmissionError,
                .postponed(.insufficientArchiveCapacity)
            )
        }

        XCTAssertEqual(try fixture.settingsStore.loadSettings().vault.transferFreeSpaceReserveGiB, 80)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        let records = try fixture.transferStore().allTransferRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(records.first).stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(records.first).destinationURL.path))
    }

    func testArchiveReloadsFloorAfterBlockingProjectionImmediatelyBeforeCapacityDecision() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(
            stage: .privateBeta,
            backupConfirmed: false,
            transferFreeSpaceReserveGiB: 1
        )
        let probe = BlockingProjectionCapacityProbe(snapshot: .safe, blockOnProjectionCall: 2)
        let runtime = try fixture.runtime(capacityProbe: probe)
        let song = fixture.song
        let operation = Task {
            try await runtime.archive(song: song, trigger: .backupCopy)
        }
        await probe.waitUntilBlocked()
        try fixture.settingsStore.updateSettings {
            $0.vault.transferFreeSpaceReserveGiB = 500
        }
        probe.release()

        do {
            _ = try await operation.value
            XCTFail("expected the operation-point floor reload to deny all byte creation")
        } catch {
            XCTAssertEqual(
                error as? VaultWriteAdmissionError,
                .postponed(.insufficientArchiveCapacity)
            )
        }

        let transfer = try XCTUnwrap(fixture.transferStore().allTransferRecords().first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: transfer.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transfer.destinationURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testOnlineRestoreReloadsFloorAfterAcknowledgedPrepareBeforeMaterialize() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(
            stage: .privateBeta,
            backupConfirmed: false,
            transferFreeSpaceReserveGiB: 1
        )
        let provider = BlockingRestorePrepareProvider()
        let runtime = try fixture.runtime(
            capacity: .safe,
            archiveProviderFactory: { _ in provider }
        )
        let archived = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
        let transfer = try XCTUnwrap(archived.transfer)
        let manifest = try XCTUnwrap(transfer.manifest)
        let restore = Task {
            try await runtime.restoreAndOpen(snapshot: archived, selectedProjectRelativePath: nil, destinationRelativePath: "Capacity check restore")
        }
        await provider.waitUntilPrepareEntered()
        try fixture.settingsStore.updateSettings {
            $0.vault.transferFreeSpaceReserveGiB = 500
        }
        await provider.releasePrepare()

        do {
            _ = try await restore.value
            XCTFail("expected post-prepare floor reload to deny materialization")
        } catch {
            XCTAssertEqual(
                error as? VaultWriteAdmissionError,
                .postponed(.insufficientArchiveCapacity)
            )
        }

        let materializeCount = await provider.materializeCount
        XCTAssertEqual(materializeCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: transfer.destinationURL.path))
        try VaultManifestBuilder().verify(manifest, at: transfer.destinationURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testEmergencyStopPreventsPersistedArchiveRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(
            stage: .privateBeta,
            backupConfirmed: false,
            emergencyStop: true
        )
        let failed = try fixture.failedDurabilityRecord()
        try fixture.transferStore().save(failed)
        let runtime = try fixture.runtime()

        await runtime.recoverAtLaunch()

        XCTAssertEqual(try fixture.transferStore().record(id: failed.id), failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.destinationURL.path))
    }

    func testPrivateBetaOnSameVolumeCopiesOnlyAndRetainsActiveCopy() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let runtime = try fixture.runtime()

        let activeVolume = try fixture.active.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let archiveVolume = try fixture.archive.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        XCTAssertEqual(String(describing: activeVolume), String(describing: archiveVolume))

        let snapshot = try await runtime.archive(song: fixture.song, trigger: .workflowDone)

        XCTAssertEqual(snapshot.transfer?.state, .archiveVerified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(snapshot.transfer).destinationURL.path))
    }

    func testRepeatedRuntimeRecoveryUsesPersistedCooldownWithoutProjectionRescan() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let failed = try fixture.failedDurabilityRecord()
        try fixture.transferStore().save(failed)
        let provider = FailingRuntimeDurabilityProvider()
        let capacityProbe = RecordingCapacityProbe(snapshot: .safe)
        let now = Date(timeIntervalSince1970: 1_000)
        let runtime = try fixture.runtime(
            capacityProbe: capacityProbe,
            archiveProviderFactory: { _ in provider },
            now: { now }
        )

        await runtime.recoverAtLaunch()
        let afterFirst = try XCTUnwrap(fixture.transferStore().record(id: failed.id))
        await runtime.recoverAtLaunch()
        let afterSecond = try XCTUnwrap(fixture.transferStore().record(id: failed.id))
        let barriers = await provider.barrierCount()

        XCTAssertEqual(barriers, 1)
        XCTAssertEqual(afterFirst.retryCount, 2)
        XCTAssertEqual(afterSecond.retryCount, afterFirst.retryCount)
        XCTAssertGreaterThan(try XCTUnwrap(afterSecond.nextRetryAt), now)
        XCTAssertEqual(capacityProbe.callCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.stagingURL.path))
    }

    func testExhaustedTransferCanBeRetriedThroughRuntimeWithoutProjectionRescan() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let failed = try fixture.failedDurabilityRecord(retryCount: 5)
        try fixture.transferStore().save(failed)
        let capacityProbe = RecordingCapacityProbe(snapshot: .safe)
        let runtime = try fixture.runtime(capacityProbe: capacityProbe)
        let snapshot = ProjectVaultRuntimeSnapshot(
            record: ProjectRecord(id: failed.projectID, canonicalTitle: "Synthetic Song", locations: []),
            transfer: failed
        )

        let retried = try await runtime.retry(snapshot: snapshot)

        XCTAssertEqual(retried.transfer?.state, .archiveVerified)
        XCTAssertEqual(retried.transfer?.retryCount, 5)
        XCTAssertNil(retried.transfer?.nextRetryAt)
        XCTAssertEqual(capacityProbe.callCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.destinationURL.path))
    }

    func testExplicitRetryRejectsIntermediateStateAndDoesNotAdvanceVerificationTimestamp() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let previousVerification = Date(timeIntervalSince1970: 30_000)
        let retryTime = Date(timeIntervalSince1970: 40_000)
        try fixture.settingsStore.updateSettings {
            $0.vault.lastSuccessfulVerificationAt = previousVerification
        }
        let failed = try fixture.failedDurabilityRecord(retryCount: 5)
        try fixture.transferStore().save(failed)
        let sourceBefore = try Data(contentsOf: failed.sourceURL.appendingPathComponent("Synthetic Song.cpr"))
        let stagingBefore = try Data(contentsOf: failed.stagingURL.appendingPathComponent("Synthetic Song.cpr"))
        let destinationExistedBefore = FileManager.default.fileExists(atPath: failed.destinationURL.path)
        let runtime = try fixture.runtime(
            archiveProviderFactory: { _ in InterruptingRetryProvider() },
            now: { retryTime }
        )
        let snapshot = ProjectVaultRuntimeSnapshot(
            record: ProjectRecord(id: failed.projectID, canonicalTitle: "Synthetic Song", locations: []),
            transfer: failed
        )
        var returned: ProjectVaultRuntimeSnapshot?

        do {
            returned = try await runtime.retry(snapshot: snapshot)
            XCTFail("an intermediate persisted retry phase must not be returned as verified success")
        } catch {}

        let persisted = try XCTUnwrap(fixture.transferStore().record(id: failed.id))
        let verification = try fixture.settingsStore
            .loadSettings().vault.lastSuccessfulVerificationAt
        XCTAssertNil(returned)
        XCTAssertEqual(persisted.id, failed.id)
        XCTAssertEqual(persisted.state, .awaitingProviderDurability)
        XCTAssertEqual(verification, previousVerification)
        XCTAssertEqual(
            try Data(contentsOf: failed.sourceURL.appendingPathComponent("Synthetic Song.cpr")),
            sourceBefore
        )
        XCTAssertEqual(
            try Data(contentsOf: failed.stagingURL.appendingPathComponent("Synthetic Song.cpr")),
            stagingBefore
        )
        XCTAssertEqual(
            FileManager.default.fileExists(atPath: failed.destinationURL.path),
            destinationExistedBefore
        )
    }

    func testEmergencyStopAlsoBlocksExplicitTransferRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false, emergencyStop: true)
        let failed = try fixture.failedDurabilityRecord(retryCount: 5)
        try fixture.transferStore().save(failed)
        let runtime = try fixture.runtime()
        let snapshot = ProjectVaultRuntimeSnapshot(
            record: ProjectRecord(id: failed.projectID, canonicalTitle: "Synthetic Song", locations: []),
            transfer: failed
        )

        do {
            _ = try await runtime.retry(snapshot: snapshot)
            XCTFail("expected Emergency Stop to block manual transfer retry")
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .emergencyStop)
        }

        XCTAssertEqual(try fixture.transferStore().record(id: failed.id), failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: failed.stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.destinationURL.path))
    }

    func testEmergencyStopRaisedAfterVerificationStillBlocksActiveDeletion() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .friends, backupConfirmed: true)
        let settingsStore = fixture.settingsStore
        let provider = RuntimePolicyChangingProvider {
            try settingsStore.updateSettings { $0.vault.automationEmergencyStop = true }
        }
        let runtime = try fixture.runtime(archiveProviderFactory: { _ in provider })

        do {
            _ = try await runtime.archive(song: fixture.song, trigger: .workflowDone)
            XCTFail("expected final Emergency Stop guard to retain Active")
        } catch {
            guard case .archiveFailed = error as? ProjectVaultRuntimeError else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        let persisted = try XCTUnwrap(fixture.transferStore().allTransferRecords().first)
        XCTAssertEqual(persisted.state, .archiveVerified)
        XCTAssertEqual(persisted.error?.origin, .removingActiveCopy)
        XCTAssertNil(persisted.nextRetryAt)
        XCTAssertTrue(try fixture.settingsStore.loadSettings().vault.automationEmergencyStop)
        XCTAssertTrue(FileManager.default.fileExists(atPath: persisted.sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: persisted.destinationURL.path))
    }

    func testDoneInFriendsRemovesOnlyAfterVerificationAndRestoreReturnsProject() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .friends, backupConfirmed: true)
        let runtime = try fixture.runtime()

        let archived = try await runtime.archive(song: fixture.song, trigger: .workflowDone)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue([VaultTransferState.archivedLocal, .archivedOnlineOnly].contains(try XCTUnwrap(archived.transfer).state))

        let restore = try await runtime.restoreAndOpen(snapshot: archived)
        XCTAssertNotNil(restore.completedAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archived.transfer!.destinationURL.path))
    }

    func testDeliveryTitleRefreshSurvivesExistingTransferAndRestore() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let runtime = try fixture.runtime()
        let original = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
        let delivery = Song(folderPath: fixture.project, originalFolderName: fixture.song.originalFolderName,
                            displayTitle: "NEW SONG", projectVersions: fixture.song.projectVersions,
                            latestCPR: fixture.song.latestCPR)
        let refreshed = try await runtime.archive(song: delivery, trigger: .backupCopy)
        XCTAssertEqual(refreshed.record.id, original.record.id)
        XCTAssertEqual(refreshed.record.canonicalTitle, "NEW SONG")
        // Fixture-only removal exercises the real archive-only restore path.
        try FileManager.default.removeItem(at: fixture.project)
        let restored = try await runtime.restoreAndOpen(snapshot: refreshed)
        XCTAssertNotNil(restored.completedAt)
        let snapshots = try await runtime.snapshots()
        XCTAssertEqual(snapshots.first { $0.record.id == original.record.id }?.record.canonicalTitle, "NEW SONG")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
    }

    func testRetryRestoreResumesExactPersistedLegacyRowAndClearsBlockerOnlyAfterUpgrade() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let store = try fixture.transferStore()
        let projectID = ProjectID()
        let transferID = UUID()
        let restoreID = UUID()
        let generation = fixture.archive
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(projectID.description, isDirectory: true)
            .appendingPathComponent("generation-\(transferID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: generation.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.project, to: generation)
        let liveManifest = try VaultManifestBuilder().build(at: generation)
        let legacyManifest = VaultManifest(
            id: liveManifest.id,
            createdAt: liveManifest.createdAt,
            entries: liveManifest.entries.map {
                VaultManifest.Entry(
                    relativePath: $0.relativePath,
                    type: $0.type,
                    byteCount: $0.byteCount,
                    modifiedAt: $0.modifiedAt,
                    sha256: $0.sha256
                )
            }
        )
        var transfer = VaultTransferRecord(
            id: transferID,
            projectID: projectID,
            sourceURL: fixture.project,
            stagingURL: fixture.archive.appendingPathComponent(".niko-staging/old"),
            destinationURL: generation,
            state: .archiveVerified,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        transfer.manifestID = legacyManifest.id
        transfer.manifest = legacyManifest
        transfer.durability = .verifiedLocal
        try store.save(transfer)
        try fixture.saveCatalogEntry(projectID: projectID)
        try FileManager.default.removeItem(at: fixture.project)
        var restore = VaultRestoreRecord(
            id: restoreID,
            projectID: projectID,
            archiveGenerationURL: generation,
            stagingURL: fixture.active.appendingPathComponent(".niko-staging/restore/\(restoreID.uuidString.lowercased())"),
            destinationURL: fixture.project,
            manifest: legacyManifest,
            archiveTransferID: transferID,
            archiveTransferState: .archiveVerified,
            requiresArchiveMaterialization: false,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        restore.failureReason = .legacyProjectionEvidenceUnavailable
        try store.saveRestore(restore)
        let runtime = try fixture.runtime(projectOpener: RuntimeNoopVaultProjectOpener())

        let completed = try await runtime.retryRestore(id: restoreID)

        XCTAssertEqual(completed.id, restoreID)
        XCTAssertNotNil(completed.completedAt)
        XCTAssertNil(completed.failureReason)
        XCTAssertNotNil(try store.record(id: transferID)?.projectionSupplement)
        let persisted = try XCTUnwrap(store.restoreRecord(id: restoreID))
        XCTAssertEqual(persisted.id, restoreID)
        XCTAssertNotNil(persisted.completedAt)
        XCTAssertNil(persisted.failureReason)
        XCTAssertTrue(try store.recoverableRestoreRecords().isEmpty)
    }

    func testRetryRestoreWithExistingSupplementClearsBlockerAndCompletesSamePersistedRow() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let store = try fixture.transferStore()
        let projectID = ProjectID()
        let transferID = UUID()
        let restoreID = UUID()
        let generation = fixture.archive
            .appendingPathComponent("generations/\(projectID.description)/generation-\(transferID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: generation.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.project, to: generation)
        let liveManifest = try VaultManifestBuilder().build(at: generation)
        let legacyManifest = VaultManifest(
            id: liveManifest.id,
            createdAt: liveManifest.createdAt,
            entries: liveManifest.entries.map {
                .init(
                    relativePath: $0.relativePath,
                    type: $0.type,
                    byteCount: $0.byteCount,
                    modifiedAt: $0.modifiedAt,
                    sha256: $0.sha256
                )
            }
        )
        var transfer = VaultTransferRecord(
            id: transferID,
            projectID: projectID,
            sourceURL: fixture.project,
            stagingURL: fixture.archive.appendingPathComponent(".niko-staging/old"),
            destinationURL: generation,
            state: .archiveVerified
        )
        transfer.manifestID = legacyManifest.id
        transfer.manifest = legacyManifest
        transfer.durability = .verifiedLocal
        try store.save(transfer)
        let supplement = try VaultProjectionSupplementBuilder().build(
            at: generation,
            verifiedAgainst: legacyManifest
        )
        _ = try store.compareAndSetProjectionSupplement(
            supplement,
            transferID: transferID,
            expectedManifest: legacyManifest,
            expectedDestinationURL: generation,
            expectedState: .archiveVerified
        )
        try fixture.saveCatalogEntry(projectID: projectID)
        try FileManager.default.removeItem(at: fixture.project)
        var restore = VaultRestoreRecord(
            id: restoreID,
            projectID: projectID,
            archiveGenerationURL: generation,
            stagingURL: fixture.active.appendingPathComponent(".niko-staging/restore/\(restoreID.uuidString.lowercased())"),
            destinationURL: fixture.project,
            manifest: legacyManifest,
            archiveTransferID: transferID,
            archiveTransferState: .archiveVerified,
            requiresArchiveMaterialization: false,
            projectionSupplement: supplement
        )
        restore.failureReason = .legacyProjectionEvidenceUnavailable
        try store.saveRestore(restore)
        let runtime = try fixture.runtime(projectOpener: RuntimeNoopVaultProjectOpener())

        let completed = try await runtime.retryRestore(id: restoreID)

        XCTAssertEqual(completed.id, restoreID)
        XCTAssertNotNil(completed.completedAt)
        XCTAssertNil(completed.failureReason)
        XCTAssertEqual(try store.allTransferRecords().map(\.id), [transferID])
        let persisted = try XCTUnwrap(store.restoreRecord(id: restoreID))
        XCTAssertEqual(persisted.id, restoreID)
        XCTAssertNotNil(persisted.completedAt)
        XCTAssertNil(persisted.failureReason)
    }

    func testCopyingPhaseNonlocalRecoveryChecksReadinessBeforeAnyLiveSourceProjection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let projectID = ProjectID()
        let restoreID = UUID()
        let generation = fixture.archive
            .appendingPathComponent("generations/\(projectID.description)/generation-ready", isDirectory: true)
        try FileManager.default.createDirectory(at: generation.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.project, to: generation)
        let manifest = try VaultManifestBuilder().build(at: generation)
        let store = try fixture.transferStore()
        var transfer = VaultTransferRecord(
            projectID: projectID,
            sourceURL: fixture.project,
            stagingURL: fixture.archive.appendingPathComponent(".niko-staging/recovery-binding"),
            destinationURL: generation,
            state: .archiveVerified
        )
        transfer.manifestID = manifest.id
        transfer.manifest = manifest
        transfer.durability = .verifiedLocal
        try store.save(transfer)
        var restore = VaultRestoreRecord(
            id: restoreID,
            projectID: projectID,
            archiveGenerationURL: generation,
            stagingURL: fixture.active.appendingPathComponent(".niko-staging/restore/\(restoreID.uuidString.lowercased())"),
            destinationURL: fixture.active.appendingPathComponent("Recovered Song"),
            manifest: manifest,
            archiveTransferID: transfer.id,
            archiveTransferState: transfer.state,
            requiresArchiveMaterialization: true,
            phase: .copyingToActiveStaging
        )
        restore.updatedAt = Date(timeIntervalSince1970: 300)
        try store.saveRestore(restore)
        let probe = RecoveryLiveProjectionProbe()
        let provider = RecoveryNonlocalProvider()
        let runtime = try fixture.runtime(
            capacityProbe: probe,
            archiveProviderFactory: { _ in provider },
            projectOpener: RuntimeNoopVaultProjectOpener()
        )

        await runtime.recoverAtLaunch()

        XCTAssertEqual(probe.liveSourceProjectionCalls, 0)
        let localityCalls = await provider.localityCallCount()
        XCTAssertGreaterThanOrEqual(localityCalls, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: restore.stagingURL.path))
        XCTAssertNotEqual(
            try fixture.transferStore().restoreRecord(id: restoreID)?.phase,
            .copyingToActiveStaging
        )
    }

    func testActiveRestoreXattrGrowthUsesFreshLiveProjectionAndDeniesBeforeStaging() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(
            stage: .friends,
            backupConfirmed: true,
            transferFreeSpaceReserveGiB: 1
        )
        let archived = try await fixture.runtime().archive(song: fixture.song, trigger: .workflowDone)
        let transfer = try XCTUnwrap(archived.transfer)
        let manifest = try XCTUnwrap(transfer.manifest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))

        let regularEntry = try XCTUnwrap(manifest.entries.first { $0.type == .regularFile })
        let archivedFile = transfer.destinationURL.appendingPathComponent(regularEntry.relativePath)
        let xattr = [UInt8](repeating: 9, count: 128 * 1_024)
        let setResult = archivedFile.withUnsafeFileSystemRepresentation { path in
            xattr.withUnsafeBytes { bytes in
                setxattr(path, "com.niko.restore-live-projection", bytes.baseAddress, bytes.count, 0, 0)
            }
        }
        XCTAssertEqual(setResult, 0)

        let projectionProbe = XattrLiveCapacityProbe(availableCapacityBytes: .max)
        let staleProjection = try projectionProbe.conservativeProjectedBytes(
            manifest: manifest,
            projectionSupplement: transfer.projectionSupplement,
            targetRootURL: fixture.active
        )
        let liveProjection = try projectionProbe.conservativeProjectedBytes(
            sourceURL: transfer.destinationURL,
            targetRootURL: fixture.active
        )
        XCTAssertGreaterThan(liveProjection, staleProjection)
        let floorBytes: Int64 = 1_073_741_824
        let (availableCapacityBytes, overflow) = staleProjection.addingReportingOverflow(floorBytes)
        XCTAssertFalse(overflow)
        let denyingProbe = XattrLiveCapacityProbe(
            availableCapacityBytes: availableCapacityBytes
        )
        let restoreRuntime = try fixture.runtime(
            capacityProbe: denyingProbe,
            projectOpener: RuntimeNoopVaultProjectOpener()
        )

        do {
            _ = try await restoreRuntime.restoreAndOpen(snapshot: archived)
            XCTFail("expected live xattr growth to breach the Active headroom floor")
        } catch {
            XCTAssertEqual(
                error as? VaultWriteAdmissionError,
                .postponed(.insufficientArchiveCapacity)
            )
        }

        let restore = try XCTUnwrap(fixture.transferStore().recoverableRestoreRecords().first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: restore.stagingURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: transfer.destinationURL.path))
    }

    func testSnapshotsRetainActiveDestinationIntegrityMismatchWithoutTrustingMissingUnboundGeneration() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let projectID = ProjectID()
        try fixture.saveCatalogEntry(projectID: projectID)
        let missingUnboundGeneration = fixture.archive
            .appendingPathComponent("generations/unbound-project/generation-unbound", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingUnboundGeneration.path))
        var restore = VaultRestoreRecord(
            projectID: projectID,
            archiveGenerationURL: missingUnboundGeneration,
            stagingURL: fixture.active.appendingPathComponent(".niko-staging/restore-integrity"),
            destinationURL: fixture.project,
            manifest: try VaultManifestBuilder().build(at: fixture.project),
            archiveTransferID: nil,
            requiresArchiveMaterialization: false,
            phase: .openingInCubase
        )
        restore.failureReason = .activeDestinationIntegrityMismatch
        restore.error = "Active integrity mismatch"
        try fixture.transferStore().saveRestore(restore)

        let snapshots = try await fixture.runtime().snapshots()
        let snapshot = try XCTUnwrap(snapshots.first { $0.record.id == projectID })

        XCTAssertEqual(snapshot.restore?.id, restore.id)
        XCTAssertEqual(snapshot.restore?.failureReason, .activeDestinationIntegrityMismatch)
        XCTAssertFalse(
            snapshot.record.locations.contains { $0.kind == .archive },
            "an unresolved persisted generation must not become trusted archive-location authority"
        )
    }

    func testSnapshotsExcludeRestoreGenerationsOutsideConfiguredGenerationsTree() async throws {
        enum InvalidLocation: CaseIterable { case outside, archiveRoot, staging }

        for location in InvalidLocation.allCases {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
            let projectID = ProjectID()
            try fixture.saveCatalogEntry(projectID: projectID)
            let archiveGenerationURL: URL
            switch location {
            case .outside:
                archiveGenerationURL = fixture.active.appendingPathComponent("Synthetic Song")
            case .archiveRoot:
                archiveGenerationURL = fixture.archive
            case .staging:
                archiveGenerationURL = fixture.archive.appendingPathComponent(".niko-staging/unsafe")
            }
            try FileManager.default.createDirectory(at: archiveGenerationURL, withIntermediateDirectories: true)
            let restore = VaultRestoreRecord(
                projectID: projectID,
                archiveGenerationURL: archiveGenerationURL,
                stagingURL: fixture.active.appendingPathComponent(".niko-staging/restore-invalid"),
                destinationURL: fixture.active.appendingPathComponent("Restored Invalid"),
                manifest: VaultManifest(entries: [])
            )
            try fixture.transferStore().saveRestore(restore)

            let snapshots = try await fixture.runtime().snapshots()

            XCTAssertNil(
                snapshots.first(where: { $0.record.id == projectID })?.restore,
                "\(location) must never become a review/retry authority"
            )
        }
    }

    func testKeepLocalStoredBySourcePathPreventsLaterAutomaticRemoval() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: true)
        let runtime = try fixture.runtime()
        let archived = try await runtime.archive(song: fixture.song, trigger: .workflowDone)
        let sourcePath = try XCTUnwrap(archived.transfer).sourceURL.path
        try fixture.settingsStore.updateSettings { settings in
            settings.vault.rolloutStage = .friends
            settings.vault.keepLocalProjectIDs.insert(sourcePath)
        }

        do {
            _ = try await runtime.archive(song: fixture.song, trigger: .workflowDone)
            XCTFail("expected Keep Local to refuse automatic archiving")
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .keepLocal)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertEqual(try fixture.transferStore().allTransferRecords().count, 1)
    }

    func testPostCopyActivityPostponementReturnsVerifiedGenerationWithoutDuplicateRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .friends, backupConfirmed: true)
        let firstTime = Date(timeIntervalSince1970: 50_000)
        let secondTime = Date(timeIntervalSince1970: 60_000)
        let clock = RuntimeTestClock(firstTime)
        let runtime = try fixture.runtime(
            activityProbe: AfterCopyBusyProbe(),
            now: { clock.value }
        )

        let snapshot = try await runtime.archive(song: fixture.song, trigger: .workflowDone)
        let postponedTransfer = try XCTUnwrap(snapshot.transfer)

        XCTAssertEqual(postponedTransfer.state, .archiveVerified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: postponedTransfer.destinationURL.path))
        XCTAssertEqual(try fixture.transferStore().allTransferRecords().count, 1)

        clock.value = secondTime
        let retryCapacityProbe = RecordingCapacityProbe(snapshot: .safe)
        let clearRuntime = try fixture.runtime(
            capacityProbe: retryCapacityProbe,
            now: { clock.value }
        )

        let completed = try await clearRuntime.archive(
            song: fixture.song,
            trigger: .workflowDone
        )
        let completedTransfer = try XCTUnwrap(completed.transfer)
        let persistedTransfers = try fixture.transferStore().allTransferRecords()

        XCTAssertEqual(completedTransfer.id, postponedTransfer.id)
        XCTAssertEqual(completedTransfer.destinationURL, postponedTransfer.destinationURL)
        XCTAssertEqual(completedTransfer.state, .archivedLocal)
        XCTAssertEqual(completedTransfer.updatedAt, secondTime)
        XCTAssertEqual(completed.record.lastVerifiedAt, secondTime)
        XCTAssertFalse(completed.record.locations.contains { $0.kind == .active })
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: completedTransfer.destinationURL.path))
        XCTAssertEqual(persistedTransfers.map(\.id), [postponedTransfer.id])
        XCTAssertEqual(retryCapacityProbe.callCount, 0, "terminal reuse must not admit or copy a new archive write")
        XCTAssertEqual(
            try fixture.settingsStore.loadSettings().vault.lastSuccessfulVerificationAt,
            secondTime
        )
    }

    func testSnapshotsProjectAvailabilityWithoutRewritingPersistedCatalog() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: true)
        let existingProject = ProjectID()
        let absentProject = ProjectID()
        let entries = [
            ProjectCatalogEntry(
                record: ProjectRecord(
                    id: existingProject,
                    canonicalTitle: "Synthetic Song",
                    locations: [ProjectLocation(
                        rootID: fixture.activeID,
                        relativePath: "Synthetic Song",
                        kind: .active,
                        availability: .missing
                    )]
                ),
                evidence: ProjectIdentityEvidence(folderName: "Synthetic Song", cubaseFiles: [])
            ),
            ProjectCatalogEntry(
                record: ProjectRecord(
                    id: absentProject,
                    canonicalTitle: "Absent Song",
                    locations: [ProjectLocation(
                        rootID: fixture.activeID,
                        relativePath: "Absent Song",
                        kind: .active,
                        availability: .local
                    )]
                ),
                evidence: ProjectIdentityEvidence(folderName: "Absent Song", cubaseFiles: [])
            ),
        ]
        try fixture.catalogStore().apply(ProjectCatalogReconciliation(
            entries: entries,
            reviews: [],
            metadataMigrations: [:]
        ))
        let runtime = try fixture.runtime()

        let projected = try await runtime.snapshots()

        let persisted = try fixture.catalogStore().loadEntries()
        XCTAssertEqual(
            projected.first { $0.record.id == existingProject }?.record.locations.first?.availability,
            .local
        )
        XCTAssertEqual(
            projected.first { $0.record.id == absentProject }?.record.locations.first?.availability,
            .missing
        )
        XCTAssertEqual(
            persisted.first { $0.record.id == existingProject }?.record.locations.first?.availability,
            .missing,
            "read-only snapshots must not rewrite catalog state outside a mutation lease"
        )
    }

    func testSnapshotsExposeNewestIncompleteRestorePhase() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let archived = try await fixture.runtime().archive(song: fixture.song, trigger: .backupCopy)
        let transfer = try XCTUnwrap(archived.transfer)
        let manifest = try XCTUnwrap(transfer.manifest)
        var restore = VaultRestoreRecord(
            projectID: transfer.projectID,
            archiveGenerationURL: transfer.destinationURL,
            stagingURL: fixture.active.appendingPathComponent(".niko-staging/restore"),
            destinationURL: fixture.active.appendingPathComponent("Restored/Synthetic Song"),
            manifest: manifest
        )
        restore.phase = .verifyingActiveStaging
        try fixture.transferStore().saveRestore(restore)

        let snapshots = try await fixture.runtime().snapshots()

        XCTAssertEqual(
            snapshots.first { $0.record.id == transfer.projectID }?.restore?.phase,
            .verifyingActiveStaging
        )
    }

    func testSupersededFailureKeepsVerifiedSuccessAuthoritativeForDoneAndManualArchive() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let store = try fixture.transferStore()
        let failed = try fixture.failedDurabilityRecord()
        try store.save(failed)
        try fixture.saveCatalogEntry(projectID: failed.projectID)

        let survivorID = UUID()
        let survivorURL = fixture.archive
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(failed.projectID.description, isDirectory: true)
            .appendingPathComponent("generation-\(survivorID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: survivorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: fixture.project, to: survivorURL)
        let survivorManifest = try VaultManifestBuilder().build(at: survivorURL)
        var survivor = VaultTransferRecord(
            id: survivorID,
            projectID: failed.projectID,
            sourceURL: fixture.project,
            stagingURL: fixture.archive.appendingPathComponent(".niko-staging/survivor"),
            destinationURL: survivorURL,
            state: .archiveVerified,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        survivor.updatedAt = Date(timeIntervalSince1970: 300)
        survivor.manifestID = survivorManifest.id
        survivor.manifest = survivorManifest
        survivor.durability = .verifiedLocal
        try store.save(survivor)
        let runtime = try fixture.runtime(now: { Date(timeIntervalSince1970: 400) })

        await runtime.recoverAtLaunch()
        let stagingRoot = fixture.archive.appendingPathComponent(".niko-staging", isDirectory: true)
        let stagingBefore = try FileManager.default.subpathsOfDirectory(atPath: stagingRoot.path)
        let done = try await runtime.archive(song: fixture.song, trigger: .workflowDone)
        let manual = try await runtime.archive(song: fixture.song, trigger: .backupCopy)

        XCTAssertEqual(done.transfer?.id, survivor.id)
        XCTAssertEqual(manual.transfer?.id, survivor.id)
        XCTAssertEqual(Set(try store.allTransferRecords().map(\.id)), [failed.id, survivor.id])
        XCTAssertEqual(
            try FileManager.default.subpathsOfDirectory(atPath: stagingRoot.path),
            stagingBefore,
            "idempotent archive actions must create no additional staging paths"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: failed.stagingURL.path),
            "obsolete staging remains preserved until managed-root/content containment is proven"
        )
    }

    func testVerifiedTerminalReuseRequiresExactCurrentSourceIdentityAndTruthfulTimestamp() async throws {
        enum SourceChange: CaseIterable, Equatable {
            case unchanged
            case content
            case add
            case remove
            case rename
        }

        for change in SourceChange.allCases {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
            let firstTime = Date(timeIntervalSince1970: 60_000)
            let secondTime = Date(timeIntervalSince1970: 70_000)
            let clock = RuntimeTestClock(firstTime)
            let runtime = try fixture.runtime(now: { clock.value })

            let first = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
            let firstTransfer = try XCTUnwrap(first.transfer)
            let firstGlobalVerification = try fixture.settingsStore
                .loadSettings().vault.lastSuccessfulVerificationAt
            XCTAssertEqual(firstGlobalVerification, firstTime, "\(change)")

            let cpr = fixture.project.appendingPathComponent("Synthetic Song.cpr")
            switch change {
            case .unchanged:
                break
            case .content:
                try Data("changed-cpr!!".utf8).write(to: cpr)
            case .add:
                try Data("new audio".utf8).write(
                    to: fixture.project.appendingPathComponent("Added.wav")
                )
            case .remove:
                try FileManager.default.removeItem(at: cpr)
            case .rename:
                try FileManager.default.moveItem(
                    at: cpr,
                    to: fixture.project.appendingPathComponent("Renamed Song.cpr")
                )
            }
            clock.value = secondTime

            let second = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
            let secondTransfer = try XCTUnwrap(second.transfer)
            let projectTransfers = try fixture.transferStore().allTransferRecords()
                .filter { $0.projectID == firstTransfer.projectID }
            let secondGlobalVerification = try fixture.settingsStore
                .loadSettings().vault.lastSuccessfulVerificationAt

            if change == .unchanged {
                XCTAssertEqual(secondTransfer.id, firstTransfer.id)
                XCTAssertEqual(secondTransfer.destinationURL, firstTransfer.destinationURL)
                XCTAssertEqual(projectTransfers.count, 1)
                XCTAssertEqual(secondTransfer.updatedAt, firstTransfer.updatedAt)
                XCTAssertEqual(secondGlobalVerification, firstGlobalVerification)
            } else {
                XCTAssertNotEqual(secondTransfer.id, firstTransfer.id, "\(change) must claim a new transfer")
                XCTAssertNotEqual(
                    secondTransfer.destinationURL,
                    firstTransfer.destinationURL,
                    "\(change) must create a new generation"
                )
                XCTAssertEqual(projectTransfers.count, 2, "\(change)")
                XCTAssertTrue(FileManager.default.fileExists(atPath: secondTransfer.destinationURL.path))
                XCTAssertEqual(secondTransfer.updatedAt, secondTime, "\(change)")
                XCTAssertEqual(secondGlobalVerification, secondTime, "\(change)")
            }
        }
    }

    func testVerifiedTerminalReuseRejectsUnusableGenerationWithoutStaleSuccessOrProviderSideEffects() async throws {
        enum UnusableGeneration: CaseIterable {
            case localMissing
            case localContentCorrupt
            case onlineMetadataUnknown
            case onlineMetadataError
            case onlinePathSizeDrift

            var isOnline: Bool {
                switch self {
                case .localMissing, .localContentCorrupt: false
                case .onlineMetadataUnknown, .onlineMetadataError, .onlinePathSizeDrift: true
                }
            }

            var providerOutcome: TerminalReuseMetadataProvider.Outcome {
                switch self {
                case .onlineMetadataError: .error
                case .onlinePathSizeDrift: .pathSizeDrift
                default: .unknown
                }
            }
        }

        for unusable in UnusableGeneration.allCases {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
            let firstTime = Date(timeIntervalSince1970: 120_000)
            let secondTime = Date(timeIntervalSince1970: 130_000)
            let clock = RuntimeTestClock(firstTime)
            let initialRuntime = try fixture.runtime(now: { clock.value })

            let first = try await initialRuntime.archive(song: fixture.song, trigger: .backupCopy)
            var terminal = try XCTUnwrap(first.transfer)
            terminal.state = unusable.isOnline ? .archivedOnlineOnly : .archivedLocal
            terminal.durability = unusable.isOnline ? .syncedToProvider : .verifiedLocal
            try fixture.transferStore().save(terminal)
            let firstVerification = try fixture.settingsStore
                .loadSettings().vault.lastSuccessfulVerificationAt
            XCTAssertEqual(firstVerification, firstTime, "\(unusable)")

            switch unusable {
            case .localMissing:
                try FileManager.default.removeItem(at: terminal.destinationURL)
            case .localContentCorrupt, .onlinePathSizeDrift:
                try Data("archive-generation-content-drift".utf8).write(
                    to: terminal.destinationURL.appendingPathComponent("Synthetic Song.cpr")
                )
            case .onlineMetadataUnknown, .onlineMetadataError:
                break
            }

            let provider = TerminalReuseMetadataProvider(outcome: unusable.providerOutcome)
            let manifestURLs = RuntimeManifestURLRecorder()
            clock.value = secondTime
            let runtime = try fixture.runtime(
                capacity: ProjectVaultCapacitySnapshot(
                    activeAvailableCapacityBytes: 0,
                    archiveAvailableCapacityBytes: 0,
                    projectedArchiveBytes: 1
                ),
                archiveProviderFactory: { _ in provider },
                sourceManifestBuilder: { url in
                    manifestURLs.record(url)
                    return try VaultManifestBuilder().build(at: url)
                },
                now: { clock.value }
            )

            var returnedTransfer: VaultTransferRecord?
            do {
                returnedTransfer = try await runtime.archive(
                    song: fixture.song,
                    trigger: .backupCopy
                ).transfer
            } catch {
                // With deliberately unsafe write capacity, rejecting the stale
                // generation must fail closed instead of publishing replacement bytes.
            }

            let providerCalls = await provider.calls()
            let persistedFirst = try XCTUnwrap(
                fixture.transferStore().record(id: terminal.id)
            )
            let finalVerification = try fixture.settingsStore
                .loadSettings().vault.lastSuccessfulVerificationAt

            XCTAssertNil(
                returnedTransfer,
                "\(unusable) must not surface the stale terminal ID as verified success"
            )
            XCTAssertEqual(persistedFirst.updatedAt, terminal.updatedAt, "\(unusable)")
            XCTAssertEqual(
                finalVerification,
                firstVerification,
                "\(unusable) must not advance global verification truth"
            )
            XCTAssertEqual(
                manifestURLs.urls,
                [fixture.project.standardizedFileURL.path],
                "\(unusable) may observe the unchanged Active manifest only once"
            )

            if unusable.isOnline {
                XCTAssertEqual(providerCalls.currentLocality, 1, "\(unusable)")
                XCTAssertEqual(
                    providerCalls.localityLocations,
                    [terminal.destinationURL.standardizedFileURL.path],
                    "\(unusable) must query only the exact persisted generation"
                )
                XCTAssertEqual(providerCalls.localityManifestIDs, [terminal.manifestID], "\(unusable)")
            } else {
                XCTAssertLessThanOrEqual(
                    manifestURLs.urls.count,
                    1,
                    "\(unusable) must not repeat manifest observation across lookup paths"
                )
                XCTAssertEqual(providerCalls.currentLocality, 0, "\(unusable)")
            }
            XCTAssertEqual(providerCalls.capabilities, 0, "\(unusable)")
            XCTAssertEqual(providerCalls.prepareForRead, 0, "\(unusable)")
            XCTAssertEqual(providerCalls.prepareForWrite, 0, "\(unusable)")
            XCTAssertEqual(providerCalls.waitUntilDurable, 0, "\(unusable)")
            XCTAssertEqual(providerCalls.materialize, 0, "\(unusable)")
            XCTAssertEqual(providerCalls.evict, 0, "\(unusable)")
        }
    }

    func testVerifiedTerminalReuseRejectsMalformedOrMissingPersistedManifestEnvelope() async throws {
        enum Corruption: CaseIterable, Equatable {
            case negativeRootAllocation
            case negativeEntryAllocation
            case negativeEntryExtendedAttributes
            case duplicatePath
            case unsafePath
            case missingRegularSHA
            case invalidRegularSHA
            case invalidDirectorySize
            case invalidDirectorySHA
            case missingParentDirectory
            case missingManifest
        }

        for corruption in Corruption.allCases {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
            let audioDirectory = fixture.project.appendingPathComponent("Audio", isDirectory: true)
            try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
            try Data("unchanged-audio".utf8).write(
                to: audioDirectory.appendingPathComponent("take.wav")
            )
            let firstTime = Date(timeIntervalSince1970: 80_000)
            let secondTime = Date(timeIntervalSince1970: 90_000)
            let clock = RuntimeTestClock(firstTime)
            let runtime = try fixture.runtime(now: { clock.value })

            let first = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
            let firstTransfer = try XCTUnwrap(first.transfer)
            let firstManifest = try XCTUnwrap(firstTransfer.manifest)
            var corrupted = firstTransfer
            if corruption == .missingManifest {
                corrupted.manifest = nil
            } else {
                var entries = firstManifest.entries
                let regularIndex = try XCTUnwrap(entries.firstIndex { $0.type == .regularFile })
                let directoryIndex = try XCTUnwrap(entries.firstIndex { $0.type == .directory })
                let regular = entries[regularIndex]
                let directory = entries[directoryIndex]
                var rootAllocatedByteCount = firstManifest.rootAllocatedByteCount

                switch corruption {
                case .negativeRootAllocation:
                    rootAllocatedByteCount = -1
                case .negativeEntryAllocation:
                    entries[regularIndex] = VaultManifest.Entry(
                        relativePath: regular.relativePath,
                        type: regular.type,
                        byteCount: regular.byteCount,
                        modifiedAt: regular.modifiedAt,
                        sha256: regular.sha256,
                        allocatedByteCount: -1,
                        extendedAttributeBytes: regular.extendedAttributeBytes
                    )
                case .negativeEntryExtendedAttributes:
                    entries[regularIndex] = VaultManifest.Entry(
                        relativePath: regular.relativePath,
                        type: regular.type,
                        byteCount: regular.byteCount,
                        modifiedAt: regular.modifiedAt,
                        sha256: regular.sha256,
                        allocatedByteCount: regular.allocatedByteCount,
                        extendedAttributeBytes: -1
                    )
                case .duplicatePath:
                    entries.append(regular)
                case .unsafePath:
                    entries[regularIndex] = VaultManifest.Entry(
                        relativePath: "../escape.cpr",
                        type: regular.type,
                        byteCount: regular.byteCount,
                        modifiedAt: regular.modifiedAt,
                        sha256: regular.sha256,
                        allocatedByteCount: regular.allocatedByteCount,
                        extendedAttributeBytes: regular.extendedAttributeBytes
                    )
                case .missingRegularSHA:
                    entries[regularIndex] = VaultManifest.Entry(
                        relativePath: regular.relativePath,
                        type: regular.type,
                        byteCount: regular.byteCount,
                        modifiedAt: regular.modifiedAt,
                        sha256: nil,
                        allocatedByteCount: regular.allocatedByteCount,
                        extendedAttributeBytes: regular.extendedAttributeBytes
                    )
                case .invalidRegularSHA:
                    entries[regularIndex] = VaultManifest.Entry(
                        relativePath: regular.relativePath,
                        type: regular.type,
                        byteCount: regular.byteCount,
                        modifiedAt: regular.modifiedAt,
                        sha256: "not-a-sha256",
                        allocatedByteCount: regular.allocatedByteCount,
                        extendedAttributeBytes: regular.extendedAttributeBytes
                    )
                case .invalidDirectorySize:
                    entries[directoryIndex] = VaultManifest.Entry(
                        relativePath: directory.relativePath,
                        type: directory.type,
                        byteCount: 1,
                        modifiedAt: directory.modifiedAt,
                        sha256: directory.sha256,
                        allocatedByteCount: directory.allocatedByteCount,
                        extendedAttributeBytes: directory.extendedAttributeBytes
                    )
                case .invalidDirectorySHA:
                    entries[directoryIndex] = VaultManifest.Entry(
                        relativePath: directory.relativePath,
                        type: directory.type,
                        byteCount: directory.byteCount,
                        modifiedAt: directory.modifiedAt,
                        sha256: String(repeating: "0", count: 64),
                        allocatedByteCount: directory.allocatedByteCount,
                        extendedAttributeBytes: directory.extendedAttributeBytes
                    )
                case .missingParentDirectory:
                    entries.remove(at: directoryIndex)
                case .missingManifest:
                    XCTFail("handled before envelope mutation")
                }
                corrupted.manifest = VaultManifest(
                    id: firstManifest.id,
                    createdAt: firstManifest.createdAt,
                    entries: entries,
                    rootAllocatedByteCount: rootAllocatedByteCount,
                    rootExtendedAttributeBytes: firstManifest.rootExtendedAttributeBytes
                )
            }
            try fixture.transferStore().save(corrupted)
            clock.value = secondTime

            let second = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
            let secondTransfer = try XCTUnwrap(second.transfer)
            let projectTransfers = try fixture.transferStore().allTransferRecords()
                .filter { $0.projectID == firstTransfer.projectID }
            let persistedFirst = try XCTUnwrap(
                fixture.transferStore().record(id: firstTransfer.id)
            )
            let globalVerification = try fixture.settingsStore
                .loadSettings().vault.lastSuccessfulVerificationAt

            XCTAssertNotEqual(
                secondTransfer.id,
                firstTransfer.id,
                "\(corruption) must not reuse a terminal row with an invalid manifest envelope"
            )
            XCTAssertEqual(projectTransfers.count, 2, "\(corruption)")
            XCTAssertEqual(
                persistedFirst.updatedAt,
                firstTime,
                "\(corruption) must not make stale verification look current"
            )
            XCTAssertEqual(globalVerification, secondTime, "\(corruption)")
        }
    }

    func testVerifiedTerminalReuseFailsClosedWhenCurrentSourceManifestCannotBeBuilt() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let firstTime = Date(timeIntervalSince1970: 100_000)
        let secondTime = Date(timeIntervalSince1970: 110_000)
        let clock = RuntimeTestClock(firstTime)
        let initialRuntime = try fixture.runtime(now: { clock.value })

        let first = try await initialRuntime.archive(song: fixture.song, trigger: .backupCopy)
        let firstTransfer = try XCTUnwrap(first.transfer)
        clock.value = secondTime
        let runtime = try fixture.runtime(
            sourceManifestBuilder: { _ in
                throw VaultManifestError.enumerationFailed("injected source observation failure")
            },
            now: { clock.value }
        )

        do {
            _ = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
            XCTFail("a source tree that cannot be manifested must fail closed")
        } catch let error as VaultManifestError {
            XCTAssertEqual(
                error,
                .enumerationFailed("injected source observation failure")
            )
        } catch {
            XCTFail("expected typed VaultManifestError, got \(error)")
        }

        let records = try fixture.transferStore().allTransferRecords()
            .filter { $0.projectID == firstTransfer.projectID }
        let persistedFirst = try XCTUnwrap(
            fixture.transferStore().record(id: firstTransfer.id)
        )
        let globalVerification = try fixture.settingsStore
            .loadSettings().vault.lastSuccessfulVerificationAt
        XCTAssertEqual(records.map(\.id), [firstTransfer.id])
        XCTAssertEqual(persistedFirst.updatedAt, firstTime)
        XCTAssertEqual(globalVerification, firstTime)
    }

    func testVerifiedTerminalComparisonObservesCurrentSourceOnlyOnceAcrossBothLookupPaths() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let counter = RuntimeManifestBuildCounter()
        let runtime = try fixture.runtime(sourceManifestBuilder: { sourceURL in
            counter.increment()
            return try VaultManifestBuilder().build(at: sourceURL)
        })

        let first = try await runtime.archive(song: fixture.song, trigger: .backupCopy)
        let firstTransfer = try XCTUnwrap(first.transfer)
        try Data("changed-cpr!!".utf8).write(
            to: fixture.project.appendingPathComponent("Synthetic Song.cpr")
        )

        let second = try await runtime.archive(song: fixture.song, trigger: .backupCopy)

        XCTAssertNotEqual(second.transfer?.id, firstTransfer.id)
        XCTAssertEqual(counter.value, 1)
    }
}

private extension LiveProjectVaultRuntimeTests {
    struct ManualArchiveProbe: VaultAutomationActivityProbing {
        let blocker: String
        func cubaseStatus() async -> VaultActivityStatus { blocker == "daw" ? .busy : .clear }
        func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { blocker == "openFiles" ? .busy : .clear }
        func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus {
            // A just-saved but closed project is a valid explicit archive request.
            .busy
        }
    }
    struct ClearProbe: VaultAutomationActivityProbing {
        func cubaseStatus() async -> VaultActivityStatus { .clear }
        func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { .clear }
        func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus { .clear }
    }
    /// The DAW check itself fails (timeout, missing tool); nothing was observed running.
    struct UncertainActivityProbe: VaultAutomationActivityProbing {
        let reason: String
        func cubaseStatus() async -> VaultActivityStatus { .uncertain(reason) }
        func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { .clear }
        func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus { .clear }
    }

    actor AfterCopyBusyProbe: VaultAutomationActivityProbing {
        private var cubaseChecks = 0

        func cubaseStatus() async -> VaultActivityStatus {
            cubaseChecks += 1
            return cubaseChecks == 1 ? .clear : .busy
        }

        func openFileStatus(in projectURL: URL) async -> VaultActivityStatus { .clear }
        func writeActivityStatus(in projectURL: URL, since: Date) async -> VaultActivityStatus { .clear }
    }

    final class Fixture {
        let root: URL
        let active: URL
        let archive: URL
        let project: URL
        let database: SQLiteArchiveDatabase
        let settingsStore: UserDefaultsSettingsStore
        let activeID = UUID()
        let archiveID = UUID()
        let suite: String

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-runtime-\(UUID().uuidString)")
            active = root.appendingPathComponent("Active")
            archive = root.appendingPathComponent("Archive")
            project = active.appendingPathComponent("Synthetic Song")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            let cpr = project.appendingPathComponent("Synthetic Song.cpr")
            try Data("synthetic-cpr".utf8).write(to: cpr)
            // Catalog evidence is read from the file itself, so its modification time must be
            // the one `song` advertises for seeded entries to match.
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: cpr.path)
            database = try SQLiteArchiveDatabase(databaseURL: root.appendingPathComponent("vault.sqlite"))
            suite = "LiveProjectVaultRuntimeTests.\(UUID().uuidString)"
            settingsStore = UserDefaultsSettingsStore(userDefaults: UserDefaults(suiteName: suite)!)
        }

        var song: Song {
            let cpr = project.appendingPathComponent("Synthetic Song.cpr")
            let version = ProjectVersion(filePath: cpr, fileName: cpr.lastPathComponent, modifiedAt: Date(timeIntervalSince1970: 1))
            return Song(
                folderPath: project,
                originalFolderName: project.lastPathComponent,
                displayTitle: "Synthetic Song",
                projectVersions: [version],
                latestCPR: version,
                workflowStatus: .done
            )
        }

        func makeAdditionalSong(named name: String) throws -> Song {
            let folder = active.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let cpr = folder.appendingPathComponent("\(name).cpr")
            try Data("additional-cpr".utf8).write(to: cpr)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: cpr.path)
            let version = ProjectVersion(
                filePath: cpr,
                fileName: cpr.lastPathComponent,
                modifiedAt: Date(timeIntervalSince1970: 2)
            )
            return Song(
                folderPath: folder,
                originalFolderName: name,
                displayTitle: name,
                projectVersions: [version],
                latestCPR: version,
                workflowStatus: .done
            )
        }

        func saveSettings(
            stage: VaultSettings.RolloutStage,
            backupConfirmed: Bool,
            transferFreeSpaceReserveGiB: Int = 5,
            emergencyStop: Bool = false
        ) throws {
            var settings = AppSettings.default
            settings.musicRoots = [
                StoredMusicRoot(id: activeID, role: .active, url: active),
                StoredMusicRoot(id: archiveID, role: .archive, url: archive)
            ]
            settings.vault = VaultSettings(
                isEnabled: true,
                activeRootID: activeID,
                archiveRootID: archiveID,
                automaticArchiving: true,
                transferFreeSpaceReserveGiB: transferFreeSpaceReserveGiB,
                rolloutStage: stage,
                automationEmergencyStop: emergencyStop,
                independentBackupConfirmed: backupConfirmed
            )
            try settingsStore.saveSettings(settings)
        }

        func failedDurabilityRecord(retryCount: Int = 1) throws -> VaultTransferRecord {
            let projectID = ProjectID()
            let transferID = UUID()
            let staging = archive
                .appendingPathComponent(".niko-staging")
                .appendingPathComponent(projectID.description)
                .appendingPathComponent(transferID.uuidString.lowercased())
            try FileManager.default.createDirectory(
                at: staging.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: project, to: staging)
            let manifest = try VaultManifestBuilder().build(at: staging)
            var record = VaultTransferRecord(
                id: transferID,
                projectID: projectID,
                sourceURL: project,
                stagingURL: staging,
                destinationURL: archive
                    .appendingPathComponent("generations")
                    .appendingPathComponent(projectID.description)
                    .appendingPathComponent("generation-\(transferID.uuidString.lowercased())"),
                state: .failedRecoverable,
                createdAt: Date(timeIntervalSince1970: 100)
            )
            record.updatedAt = Date(timeIntervalSince1970: 200)
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

        func saveCatalogEntry(projectID: ProjectID) throws {
            let entry = ProjectCatalogEntry(
                record: ProjectRecord(
                    id: projectID,
                    canonicalTitle: "Synthetic Song",
                    locations: [ProjectLocation(
                        rootID: activeID,
                        relativePath: project.lastPathComponent,
                        kind: .active,
                        availability: .local
                    )],
                    workflowState: .done
                ),
                evidence: ProjectIdentityEvidence(
                    folderName: project.lastPathComponent,
                    cubaseFiles: [ProjectFileIdentity(
                        name: "Synthetic Song.cpr",
                        byteCount: 13,
                        modifiedAt: Date(timeIntervalSince1970: 1)
                    )]
                )
            )
            try catalogStore().apply(ProjectCatalogReconciliation(
                entries: [entry],
                reviews: [],
                metadataMigrations: [:]
            ))
        }

        func runtime(
            activityProbe: any VaultAutomationActivityProbing = ClearProbe(),
            capacity: ProjectVaultCapacitySnapshot = .safe,
            capacityProbe: (any ProjectVaultCapacityProbing)? = nil,
            archiveProviderFactory: @escaping @Sendable (URL) -> any ArchiveStorageProvider = {
                LocalFolderArchiveStorage(root: $0)
            },
            projectOpener: any VaultProjectOpening = SafeVaultProjectOpener(),
            sourceManifestBuilder: @escaping @Sendable (URL) throws -> VaultManifest = {
                try VaultManifestBuilder().build(at: $0)
            },
            now: @escaping @Sendable () -> Date = Date.init
        ) throws -> LiveProjectVaultRuntime {
            try LiveProjectVaultRuntime(
                settingsStore: settingsStore,
                transferStore: transferStore(),
                catalogStore: catalogStore(),
                projectOpener: projectOpener,
                activityProbe: activityProbe,
                capacityProbe: capacityProbe ?? FixedCapacityProbe(snapshot: capacity),
                archiveProviderFactory: archiveProviderFactory,
                sourceManifestBuilder: sourceManifestBuilder,
                now: now
            )
        }

        func transferStore() throws -> SQLiteVaultTransferStore {
            try SQLiteVaultTransferStore(database: database)
        }

        func catalogStore() throws -> SQLiteProjectCatalogStore {
            try SQLiteProjectCatalogStore(database: database)
        }

        func cleanup() {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private struct RuntimeNoopVaultProjectOpener: VaultProjectOpening {
    func openProject(at projectURL: URL, allowedRoot: URL) throws -> MusicItemOpener.OpenResult? {
        nil
    }
}

private final class RuntimeTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) { storedValue = value }

    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private final class RuntimeManifestBuildCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    func increment() {
        lock.withLock { storedValue += 1 }
    }

    var value: Int {
        lock.withLock { storedValue }
    }
}

private final class RuntimeManifestURLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURLs: [String] = []

    func record(_ url: URL) {
        lock.withLock { storedURLs.append(url.standardizedFileURL.path) }
    }

    var urls: [String] {
        lock.withLock { storedURLs }
    }
}

private actor TerminalReuseMetadataProvider: ArchiveStorageProvider {
    enum Outcome: Sendable {
        case unknown
        case error
        case pathSizeDrift
    }

    struct Calls: Sendable {
        var capabilities = 0
        var currentLocality = 0
        var localityLocations: [String] = []
        var localityManifestIDs: [UUID?] = []
        var prepareForRead = 0
        var prepareForWrite = 0
        var waitUntilDurable = 0
        var materialize = 0
        var evict = 0
    }

    private let outcome: Outcome
    private var recorded = Calls()

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func capabilities() async throws -> StorageCapabilities {
        recorded.capabilities += 1
        return .init(
            waitsForDurability: true,
            supportsMaterialization: true,
            supportsEviction: true
        )
    }

    func currentLocality(
        at location: URL,
        manifest: VaultManifest
    ) async throws -> ArchiveStorageLocality {
        recorded.currentLocality += 1
        recorded.localityLocations.append(location.standardizedFileURL.path)
        recorded.localityManifestIDs.append(manifest.id)
        switch outcome {
        case .unknown:
            return .unknown
        case .error:
            throw FileProviderArchiveStorageError.lookupUnavailable
        case .pathSizeDrift:
            guard let regular = manifest.entries.first(where: { $0.type == .regularFile }) else {
                return .unknown
            }
            let observedByteCount = regular.byteCount + 1
            return observedByteCount == regular.byteCount ? .fullyLocalCurrent : .unknown
        }
    }

    func prepareForRead(_ location: URL) async throws {
        recorded.prepareForRead += 1
    }

    func prepareForWrite(at root: URL) async throws {
        recorded.prepareForWrite += 1
    }

    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        recorded.waitUntilDurable += 1
        return .syncedToProvider
    }

    func materialize(_ location: URL) async throws {
        recorded.materialize += 1
    }

    func evictIfSupported(_ location: URL) async throws -> EvictionResult {
        recorded.evict += 1
        return .unsupported
    }

    func calls() -> Calls { recorded }
}

private extension ProjectVaultCapacitySnapshot {
    static let safe = ProjectVaultCapacitySnapshot(
        activeAvailableCapacityBytes: 500 * 1_073_741_824,
        archiveAvailableCapacityBytes: 500 * 1_073_741_824,
        projectedArchiveBytes: 1_073_741_824
    )
}

private struct FixedCapacityProbe: ProjectVaultCapacityProbing {
    let snapshotValue: ProjectVaultCapacitySnapshot

    init(snapshot: ProjectVaultCapacitySnapshot) { snapshotValue = snapshot }

    func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot {
        snapshotValue
    }
}

private final class RecoveryLiveProjectionProbe: ProjectVaultCapacityProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var storedLiveSourceProjectionCalls = 0

    var liveSourceProjectionCalls: Int {
        lock.withLock { storedLiveSourceProjectionCalls }
    }

    func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot {
        .safe
    }

    func conservativeProjectedBytes(sourceURL: URL, targetRootURL: URL) throws -> Int64 {
        lock.withLock { storedLiveSourceProjectionCalls += 1 }
        return 1_073_741_824
    }

    func availableCapacityBytes(at targetRootURL: URL) throws -> Int64 {
        500 * 1_073_741_824
    }
}

private struct XattrLiveCapacityProbe: ProjectVaultCapacityProbing {
    let availableCapacityBytesValue: Int64
    private let foundation = FoundationProjectVaultCapacityProbe()

    init(availableCapacityBytes: Int64) {
        self.availableCapacityBytesValue = availableCapacityBytes
    }

    func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot {
        ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: availableCapacityBytesValue,
            archiveAvailableCapacityBytes: availableCapacityBytesValue,
            projectedArchiveBytes: try foundation.conservativeProjectedBytes(
                sourceURL: sourceURL,
                targetRootURL: archiveRootURL
            )
        )
    }

    func availableCapacityBytes(at targetRootURL: URL) throws -> Int64 {
        availableCapacityBytesValue
    }

    func conservativeProjectedBytes(sourceURL: URL, targetRootURL: URL) throws -> Int64 {
        try foundation.conservativeProjectedBytes(sourceURL: sourceURL, targetRootURL: targetRootURL)
    }

    func conservativeProjectedBytes(
        manifest: VaultManifest,
        projectionSupplement: VaultProjectionSupplement?,
        targetRootURL: URL
    ) throws -> Int64 {
        try foundation.conservativeProjectedBytes(
            manifest: manifest,
            projectionSupplement: projectionSupplement,
            targetRootURL: targetRootURL
        )
    }
}

private actor RecoveryNonlocalProvider: ArchiveStorageProvider {
    private var localityCalls = 0

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: true, supportsEviction: false)
    }

    func currentLocality(at location: URL, manifest: VaultManifest) async throws -> ArchiveStorageLocality {
        localityCalls += 1
        return .materializationRequired
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }

    func localityCallCount() -> Int { localityCalls }
}

private final class RecordingCapacityProbe: ProjectVaultCapacityProbing, @unchecked Sendable {
    private let lock = NSLock()
    private let snapshotValue: ProjectVaultCapacitySnapshot
    private var calls = 0

    init(snapshot: ProjectVaultCapacitySnapshot) { snapshotValue = snapshot }

    var callCount: Int { lock.withLock { calls } }

    func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot {
        lock.withLock { calls += 1 }
        return snapshotValue
    }
}

private final class BlockingCapacityProbe: ProjectVaultCapacityProbing, @unchecked Sendable {
    private let condition = NSCondition()
    private let snapshotValue: ProjectVaultCapacitySnapshot
    private var calls = 0
    private var released = false

    init(snapshot: ProjectVaultCapacitySnapshot) { snapshotValue = snapshot }

    var callCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return calls
    }

    func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot {
        condition.lock()
        calls += 1
        condition.broadcast()
        while !released { condition.wait() }
        condition.unlock()
        return snapshotValue
    }

    func waitUntilFirstLookup() async {
        while callCount == 0 { await Task.yield() }
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class BlockingProjectionCapacityProbe: ProjectVaultCapacityProbing, @unchecked Sendable {
    private let condition = NSCondition()
    private let snapshotValue: ProjectVaultCapacitySnapshot
    private let blockOnProjectionCall: Int
    private var projectionCalls = 0
    private var blocked = false
    private var released = false

    init(snapshot: ProjectVaultCapacitySnapshot, blockOnProjectionCall: Int) {
        self.snapshotValue = snapshot
        self.blockOnProjectionCall = blockOnProjectionCall
    }

    func snapshot(sourceURL: URL, archiveRootURL: URL) throws -> ProjectVaultCapacitySnapshot {
        snapshotValue
    }

    func writeSnapshot(sourceURL: URL, targetRootURL: URL) throws -> ProjectVaultWriteCapacitySnapshot {
        waitAtProjectionBoundaryIfNeeded()
        return ProjectVaultWriteCapacitySnapshot(
            availableCapacityBytes: snapshotValue.archiveAvailableCapacityBytes,
            projectedCopyBytes: snapshotValue.projectedArchiveBytes
        )
    }

    func conservativeProjectedBytes(sourceURL: URL, targetRootURL: URL) throws -> Int64 {
        waitAtProjectionBoundaryIfNeeded()
        return snapshotValue.projectedArchiveBytes
    }

    func availableCapacityBytes(at targetRootURL: URL) throws -> Int64 {
        snapshotValue.archiveAvailableCapacityBytes
    }

    func waitUntilBlocked() async {
        while !hasBlocked { await Task.yield() }
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    private func waitAtProjectionBoundaryIfNeeded() {
        condition.lock()
        projectionCalls += 1
        if projectionCalls == blockOnProjectionCall {
            blocked = true
            condition.broadcast()
            while !released { condition.wait() }
        }
        condition.unlock()
    }

    private var hasBlocked: Bool {
        condition.lock()
        defer { condition.unlock() }
        return blocked
    }
}

private final class ThreadSafeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool { lock.withLock { storedValue } }
    func set() { lock.withLock { storedValue = true } }
}

private actor SettingsFloorRaisingProvider: ArchiveStorageProvider {
    private let raiseFloor: @Sendable () throws -> Void

    init(raiseFloor: @escaping @Sendable () throws -> Void) {
        self.raiseFloor = raiseFloor
    }

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: false, supportsEviction: false)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws { try raiseFloor() }
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }
    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

private actor BlockingRestorePrepareProvider: ArchiveStorageProvider {
    private var prepareEntered = false
    private var prepareReleased = false
    private var prepareWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var materializeCount = 0

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: true, supportsEviction: false)
    }

    func currentLocality(
        at location: URL,
        manifest: VaultManifest
    ) async throws -> ArchiveStorageLocality {
        .materializationRequired
    }

    func prepareForRead(_ location: URL) async throws {
        prepareEntered = true
        let waiters = prepareWaiters
        prepareWaiters.removeAll()
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
        await withCheckedContinuation { prepareWaiters.append($0) }
    }

    func releasePrepare() {
        prepareReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor FailingRuntimeDurabilityProvider: ArchiveStorageProvider {
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

private final class CapacityLookupRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCapacityURLs: [String] = []
    private var storedBlockSizeURLs: [String] = []

    var capacityURLs: [String] { lock.withLock { storedCapacityURLs } }
    var blockSizeURLs: [String] { lock.withLock { storedBlockSizeURLs } }

    func recordCapacity(_ url: URL) {
        lock.withLock { storedCapacityURLs.append(url.path) }
    }

    func recordBlockSize(_ url: URL) {
        lock.withLock { storedBlockSizeURLs.append(url.path) }
    }
}

private actor BlockingRuntimeDurabilityProvider: ArchiveStorageProvider {
    private let failsAtBarrier: Bool
    private var barrierCount = 0
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var barrierWaiters: [CheckedContinuation<Void, Never>] = []

    init(failsAtBarrier: Bool = false) {
        self.failsAtBarrier = failsAtBarrier
    }

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: true, supportsMaterialization: true, supportsEviction: false)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}

    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        barrierCount += 1
        if barrierCount == 1 {
            let waiters = entryWaiters
            entryWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        if !released {
            await withCheckedContinuation { barrierWaiters.append($0) }
        }
        if failsAtBarrier {
            throw FileProviderArchiveStorageError.durabilityUnavailable
        }
        return .verifiedLocal
    }

    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }

    func waitUntilFirstBarrier() async {
        if barrierCount > 0 { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func releaseBarriers() {
        released = true
        let waiters = barrierWaiters
        barrierWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func firstBarrierCount() -> Int { barrierCount }
}

private actor BlockingMaterializeProvider: ArchiveStorageProvider {
    private var materializeStarted = false
    private var materializeFinished = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: true, supportsEviction: false)
    }

    func currentLocality(
        at location: URL,
        manifest: VaultManifest
    ) async throws -> ArchiveStorageLocality {
        materializeFinished ? .fullyLocalCurrent : .materializationRequired
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability { .verifiedLocal }

    func materialize(_ location: URL) async throws {
        materializeStarted = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        materializeFinished = true
    }

    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }

    func waitUntilMaterialize() async {
        if materializeStarted { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor RuntimePolicyChangingProvider: ArchiveStorageProvider {
    private let changePolicy: @Sendable () throws -> Void
    private var barrierCount = 0

    init(changePolicy: @escaping @Sendable () throws -> Void) {
        self.changePolicy = changePolicy
    }

    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: false, supportsMaterialization: true, supportsEviction: false)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        barrierCount += 1
        if barrierCount == 2 { try changePolicy() }
        return .verifiedLocal
    }
    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

private actor InterruptingRetryProvider: ArchiveStorageProvider {
    func capabilities() async throws -> StorageCapabilities {
        .init(waitsForDurability: true, supportsMaterialization: false, supportsEviction: false)
    }

    func prepareForRead(_ location: URL) async throws {}
    func prepareForWrite(at root: URL) async throws {}
    func waitUntilDurable(_ location: URL) async throws -> VaultDurability {
        throw VaultTransferInterruption()
    }
    func materialize(_ location: URL) async throws {}
    func evictIfSupported(_ location: URL) async throws -> EvictionResult { .unsupported }
}

// MARK: - Catalog identity from fresh source evidence (Slice 1)

extension LiveProjectVaultRuntimeTests {
    /// The two live failure paths: a Done song evaluated once from the cached index (whole-second
    /// timestamps) and once from a fresh scan (nanoseconds) must not fork into two catalog entries.
    func testArchiveDoneSongFromCachedAndFreshRepresentationsWritesOneCatalogEntry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let cpr = fixture.project.appendingPathComponent("Synthetic Song.cpr")
        let fractional = Date(timeIntervalSinceReferenceDate: 805_032_438.412_305_4)
        try FileManager.default.setAttributes([.modificationDate: fractional], ofItemAtPath: cpr.path)
        let onDisk = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: cpr.path)[.modificationDate] as? Date)
        guard onDisk.timeIntervalSinceReferenceDate != onDisk.timeIntervalSinceReferenceDate.rounded(.down) else {
            throw XCTSkip("this volume floors modification times to whole seconds; the precision case cannot be exercised here")
        }

        var fresh = try XCTUnwrap(MusicArchiveScanner().scan(roots: [fixture.active]).songs.first {
            $0.originalFolderName == "Synthetic Song"
        })
        fresh.workflowStatus = .done
        let indexStore = try SQLiteArchiveIndexStore(database: fixture.database)
        try indexStore.save(ArchiveIndexSnapshot(roots: [fixture.active.path], songs: [fresh], scannedAt: Date()))
        let cached = try XCTUnwrap(try indexStore.loadLatest()?.songs.first)
        XCTAssertEqual(fresh.projectVersions.first?.modifiedAt, onDisk)
        XCTAssertNotEqual(cached.projectVersions.first?.modifiedAt, onDisk, "the cached index is expected to drop fractional seconds")

        let gib: Int64 = 1_073_741_824
        let blocked = try fixture.runtime(capacity: ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: 7 * gib,
            archiveAvailableCapacityBytes: 7 * gib,
            projectedArchiveBytes: 4 * gib
        ))
        for song in [cached, fresh, cached] {
            do {
                _ = try await blocked.archive(song: song, trigger: .workflowDone)
                XCTFail("expected capacity postponement after the catalog entry is recorded")
            } catch {
                XCTAssertEqual(error as? ProjectVaultRuntimeError, .activityPostponed(.insufficientArchiveCapacity))
            }
        }

        let entries = try fixture.catalogStore().loadEntries()
        XCTAssertEqual(entries.count, 1, "cached and fresh representations of one folder must share one identity")
        XCTAssertTrue(try fixture.catalogStore().loadReviews().isEmpty)
        XCTAssertEqual(
            entries.first?.evidence.cubaseFiles,
            [ProjectFileIdentity(name: "Synthetic Song.cpr", byteCount: 13, modifiedAt: onDisk)],
            "stored evidence comes from the file on disk at full precision"
        )
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
    }

    func testArchiveDoneSongWithVanishedVersionWritesNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let seeded = ProjectID()
        let decision = try fixture.seedCatalogWithMetadataAndDecision(projectID: seeded)
        let before = try fixture.catalogRows()
        try FileManager.default.removeItem(at: fixture.project.appendingPathComponent("Synthetic Song.cpr"))

        do {
            _ = try await fixture.runtime().archive(song: fixture.song, trigger: .workflowDone)
            XCTFail("a song whose listed project file is gone must be refused")
        } catch {
            XCTAssertEqual(
                error as? ProjectVaultRuntimeError,
                .sourceInventoryIncomplete(title: "Synthetic Song", reason: "“Synthetic Song.cpr” is no longer in the project folder")
            )
        }

        XCTAssertEqual(try fixture.catalogRows(), before, "an incomplete inventory must not touch catalog, reviews, metadata, or history")
        XCTAssertEqual(try fixture.catalogStore().loadEntries().map(\.record.id), [seeded])
        XCTAssertEqual(try fixture.catalogStore().loadReviews(), [decision])
        try fixture.assertSeededMetadataUnchanged(projectID: seeded)
        XCTAssertTrue(try fixture.transferStore().allTransferRecords().isEmpty)
    }

    func testArchiveDoneSongWhoseFolderIsGoneWritesNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        try fixture.saveCatalogEntry(projectID: ProjectID())
        let before = try fixture.catalogRows()
        try FileManager.default.removeItem(at: fixture.project)

        do {
            _ = try await fixture.runtime().archive(song: fixture.song, trigger: .workflowDone)
            XCTFail("a song whose folder is gone must be refused")
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .sourceUnavailable(title: "Synthetic Song"))
        }

        XCTAssertEqual(try fixture.catalogRows(), before)
    }

    func testArchiveDoneSongWithUnreadableSubfolderWritesNothing() async throws {
        try XCTSkipIf(geteuid() == 0, "root ignores directory permissions")
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        try fixture.saveCatalogEntry(projectID: ProjectID())
        let before = try fixture.catalogRows()
        let nested = fixture.project.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: nested.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nested.path) }

        do {
            _ = try await fixture.runtime().archive(song: fixture.song, trigger: .workflowDone)
            XCTFail("a partially enumerable folder must be refused")
        } catch {
            XCTAssertEqual(
                error as? ProjectVaultRuntimeError,
                .sourceInventoryIncomplete(title: "Synthetic Song", reason: "“Nested” could not be enumerated")
            )
        }

        XCTAssertEqual(try fixture.catalogRows(), before)
    }

    /// A catalog row written from a cached observation carries whole-second timestamps. Once the
    /// fresh evidence differs, the runtime must refuse rather than create a second identity.
    func testLegacyWholeSecondEntryAtUniqueLocationRefusesInsteadOfForking() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let cpr = fixture.project.appendingPathComponent("Synthetic Song.cpr")
        let fractional = Date(timeIntervalSinceReferenceDate: 805_032_438.412_305_4)
        try FileManager.default.setAttributes([.modificationDate: fractional], ofItemAtPath: cpr.path)
        let onDisk = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: cpr.path)[.modificationDate] as? Date)
        guard onDisk.timeIntervalSinceReferenceDate != onDisk.timeIntervalSinceReferenceDate.rounded(.down) else {
            throw XCTSkip("this volume floors modification times to whole seconds; the precision case cannot be exercised here")
        }
        let legacy = ProjectID()
        let decision = try fixture.seedCatalogWithMetadataAndDecision(
            projectID: legacy,
            modifiedAt: Date(timeIntervalSinceReferenceDate: onDisk.timeIntervalSinceReferenceDate.rounded(.down))
        )
        let before = try fixture.catalogRows()
        var fresh = try XCTUnwrap(MusicArchiveScanner().scan(roots: [fixture.active]).songs.first {
            $0.originalFolderName == "Synthetic Song"
        })
        fresh.workflowStatus = .done

        do {
            _ = try await fixture.runtime().archive(song: fresh, trigger: .workflowDone)
            XCTFail("legacy evidence at the folder's location must be refused, not forked")
        } catch {
            XCTAssertEqual(
                error as? ProjectVaultRuntimeError,
                .identityAmbiguous(
                    title: "Synthetic Song",
                    reason: "the catalog entry for this folder does not match its current project files"
                )
            )
        }

        XCTAssertEqual(try fixture.catalogRows(), before, "the legacy row, its review decision, metadata, and history stay exactly as they were")
        XCTAssertEqual(try fixture.catalogStore().loadEntries().map(\.record.id), [legacy])
        XCTAssertEqual(try fixture.catalogStore().loadReviews(), [decision])
        try fixture.assertSeededMetadataUnchanged(projectID: legacy)
    }

    func testDuplicateCatalogEntriesForOneFolderRefuseArchiveWithoutWriting() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        let first = ProjectID()
        let second = ProjectID()
        try fixture.saveCatalogEntries(projectIDs: [first, second])
        let before = try fixture.catalogRows()

        do {
            _ = try await fixture.runtime().archive(song: fixture.song, trigger: .workflowDone)
            XCTFail("two entries for one folder must be refused")
        } catch {
            XCTAssertEqual(
                error as? ProjectVaultRuntimeError,
                .identityAmbiguous(title: "Synthetic Song", reason: "2 catalog entries share this folder")
            )
        }

        XCTAssertEqual(try fixture.catalogRows(), before)
        XCTAssertEqual(Set(try fixture.catalogStore().loadEntries().map(\.record.id)), [first, second])
    }

    /// Ordinary behaviour must hold on fresh evidence: a scanned song makes a backup copy, is
    /// archived, restored, and archived again, and the catalog keeps one identity whose evidence
    /// is the file on disk.
    func testScannedSongArchivesRestoresAndReArchivesOnOneIdentityWithDiskEvidence() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: true)
        try fixture.settingsStore.updateSettings { $0.vault.automaticArchiving = false }
        let cpr = fixture.project.appendingPathComponent("Synthetic Song.cpr")
        let onDisk = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: cpr.path)[.modificationDate] as? Date)
        let scanned = try XCTUnwrap(MusicArchiveScanner().scan(roots: [fixture.active]).songs.first {
            $0.originalFolderName == "Synthetic Song"
        })
        let runtime = try fixture.runtime(projectOpener: RuntimeNoopVaultProjectOpener())
        let before = try VaultManifestBuilder().build(at: fixture.project)

        let copy = try await runtime.archive(song: scanned, trigger: .backupCopy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.path))
        let entries = try fixture.catalogStore().loadEntries()
        XCTAssertEqual(entries.map(\.record.id), [copy.record.id])
        XCTAssertEqual(
            entries.first?.evidence.cubaseFiles,
            [ProjectFileIdentity(name: "Synthetic Song.cpr", byteCount: 13, modifiedAt: onDisk)],
            "stored evidence is the file on disk, not the scanned representation"
        )

        let archived = try await runtime.archive(song: scanned, trigger: .manual)
        XCTAssertEqual(archived.record.id, copy.record.id)
        XCTAssertEqual(archived.transfer?.id, copy.transfer?.id)
        XCTAssertEqual(archived.transfer?.state, .archivedLocal)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))

        let restored = try await runtime.restoreAndOpen(snapshot: archived)
        XCTAssertNotNil(restored.completedAt)
        try VaultManifestBuilder().verify(before, at: fixture.project)

        let again = try await runtime.archive(song: scanned, trigger: .manual)
        XCTAssertEqual(again.record.id, copy.record.id)
        XCTAssertEqual(again.transfer?.id, copy.transfer?.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.project.path))
        XCTAssertEqual(try fixture.catalogStore().loadEntries().map(\.record.id), [copy.record.id])
        XCTAssertTrue(try fixture.catalogStore().loadReviews().isEmpty)
        XCTAssertEqual(try fixture.transferStore().allTransferRecords().count, 1)
    }

    /// An entry that claims the observed folder and another still-existing Active folder used to
    /// be set aside as a "separate sibling" before reconciliation, which forked the observed folder
    /// into a second identity. Such an entry must reach the reconciler.
    func testEntryClaimingObservedFolderAndAnotherExistingFolderIsReusedNotForked() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        _ = try fixture.makeAdditionalSong(named: "Sibling")
        let shared = ProjectID()
        try fixture.saveCatalogEntry(projectID: shared, activePaths: ["Synthetic Song", "Sibling"], byteCount: 13)
        let gib: Int64 = 1_073_741_824
        let blocked = try fixture.runtime(capacity: ProjectVaultCapacitySnapshot(
            activeAvailableCapacityBytes: 7 * gib,
            archiveAvailableCapacityBytes: 7 * gib,
            projectedArchiveBytes: 4 * gib
        ))

        do {
            _ = try await blocked.archive(song: fixture.song, trigger: .workflowDone)
            XCTFail("expected capacity postponement after the catalog entry is reused")
        } catch {
            XCTAssertEqual(error as? ProjectVaultRuntimeError, .activityPostponed(.insufficientArchiveCapacity))
        }

        let entries = try fixture.catalogStore().loadEntries()
        XCTAssertEqual(entries.map(\.record.id), [shared], "the entry claiming this folder is reused, never forked")
        XCTAssertEqual(Set(entries.first?.record.locations.map(\.relativePath) ?? []), ["Synthetic Song", "Sibling"])
        XCTAssertTrue(try fixture.catalogStore().loadReviews().isEmpty)
    }

    func testEntryClaimingObservedFolderAndAnotherExistingFolderWithOtherEvidenceIsAmbiguous() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.saveSettings(stage: .privateBeta, backupConfirmed: false)
        _ = try fixture.makeAdditionalSong(named: "Sibling")
        let shared = ProjectID()
        try fixture.saveCatalogEntry(projectID: shared, activePaths: ["Synthetic Song", "Sibling"], byteCount: 99)
        let before = try fixture.catalogRows()

        do {
            _ = try await fixture.runtime().archive(song: fixture.song, trigger: .workflowDone)
            XCTFail("mismatched evidence at a claimed folder must be refused")
        } catch {
            XCTAssertEqual(
                error as? ProjectVaultRuntimeError,
                .identityAmbiguous(
                    title: "Synthetic Song",
                    reason: "the catalog entry for this folder does not match its current project files"
                )
            )
        }

        XCTAssertEqual(try fixture.catalogRows(), before)
        XCTAssertEqual(try fixture.catalogStore().loadEntries().map(\.record.id), [shared])
    }
}

private extension LiveProjectVaultRuntimeTests.Fixture {
    func saveCatalogEntry(projectID: ProjectID, modifiedAt: Date) throws {
        try saveCatalogEntries(projectIDs: [projectID], modifiedAt: modifiedAt)
    }

    /// One catalog entry plus everything a refusal must leave alone: a persisted Keep-separate
    /// decision, path-keyed metadata with a status change, and ProjectID-keyed metadata.
    @discardableResult
    func seedCatalogWithMetadataAndDecision(
        projectID: ProjectID,
        modifiedAt: Date = Date(timeIntervalSince1970: 1)
    ) throws -> ProjectIdentityReview {
        var decision = ProjectIdentityReview(
            existingProjectID: projectID,
            candidateProjectID: ProjectID(rawValue: UUID(uuidString: "0A0A0A0A-0000-4000-8000-000000000AAA")!),
            reason: "Reviewed earlier"
        )
        decision.resolution = .keepSeparate
        try saveCatalogEntries(projectIDs: [projectID], modifiedAt: modifiedAt, reviews: [decision])
        let metadataStore = try SQLiteSongUserMetadataStore(database: database)
        try metadataStore.upsert(SongUserMetadata(songID: project.path, appNote: "path-keyed note", workflowStatus: .prod))
        try metadataStore.upsert(SongUserMetadata(songID: project.path, appNote: "path-keyed note", workflowStatus: .done))
        try metadataStore.upsert(SongUserMetadata(songID: projectID.description, virtualTitle: "ID-keyed title", aliases: ["alias"]))
        return decision
    }

    func assertSeededMetadataUnchanged(projectID: ProjectID, file: StaticString = #filePath, line: UInt = #line) throws {
        let metadataStore = try SQLiteSongUserMetadataStore(database: database)
        let metadata = try metadataStore.loadAll()
        XCTAssertEqual(metadata[project.path]?.appNote, "path-keyed note", file: file, line: line)
        XCTAssertEqual(metadata[project.path]?.workflowStatus, .done, file: file, line: line)
        XCTAssertEqual(metadata[projectID.description]?.virtualTitle, "ID-keyed title", file: file, line: line)
        XCTAssertEqual(metadata[projectID.description]?.aliases, ["alias"], file: file, line: line)
        XCTAssertEqual(try metadataStore.statusHistory(forSongID: project.path).map(\.toStatus), [.prod, .done], file: file, line: line)
    }

    /// One entry claiming several Active folders at once.
    func saveCatalogEntry(projectID: ProjectID, activePaths: [String], byteCount: Int64) throws {
        let entry = ProjectCatalogEntry(
            record: ProjectRecord(
                id: projectID,
                canonicalTitle: "Synthetic Song",
                locations: activePaths.map {
                    ProjectLocation(rootID: activeID, relativePath: $0, kind: .active, availability: .local)
                },
                workflowState: .done
            ),
            evidence: ProjectIdentityEvidence(
                folderName: project.lastPathComponent,
                cubaseFiles: [ProjectFileIdentity(name: "Synthetic Song.cpr", byteCount: byteCount, modifiedAt: Date(timeIntervalSince1970: 1))]
            )
        )
        try catalogStore().apply(ProjectCatalogReconciliation(entries: [entry], reviews: [], metadataMigrations: [:]))
    }

    func saveCatalogEntries(
        projectIDs: [ProjectID],
        modifiedAt: Date = Date(timeIntervalSince1970: 1),
        reviews: [ProjectIdentityReview] = []
    ) throws {
        let entries = projectIDs.map { projectID in
            ProjectCatalogEntry(
                record: ProjectRecord(
                    id: projectID,
                    canonicalTitle: "Synthetic Song",
                    locations: [ProjectLocation(
                        rootID: activeID,
                        relativePath: project.lastPathComponent,
                        kind: .active,
                        availability: .local
                    )],
                    workflowState: .done
                ),
                evidence: ProjectIdentityEvidence(
                    folderName: project.lastPathComponent,
                    cubaseFiles: [ProjectFileIdentity(name: "Synthetic Song.cpr", byteCount: 13, modifiedAt: modifiedAt)]
                )
            )
        }
        try catalogStore().apply(ProjectCatalogReconciliation(entries: entries, reviews: reviews, metadataMigrations: [:]))
    }

    /// Raw catalog, review, metadata, and status-history rows, for byte-level "nothing changed"
    /// assertions. Metadata tables are included only once a metadata store has created them.
    func catalogRows() throws -> [String] {
        try database.withConnection { db in
            var rows: [String] = []
            let optionalTables = [
                "song_metadata": "SELECT song_id || '\u{1F}' || COALESCE(virtual_title, '') || '\u{1F}' || aliases_json || '\u{1F}' || COALESCE(app_note, '') || '\u{1F}' || COALESCE(workflow_status, '') || '\u{1F}' || updated_at FROM song_metadata ORDER BY song_id;",
                "song_status_history": "SELECT id || '\u{1F}' || song_id || '\u{1F}' || COALESCE(from_status, '') || '\u{1F}' || COALESCE(to_status, '') || '\u{1F}' || changed_at FROM song_status_history ORDER BY id;",
            ]
            var queries = [
                "SELECT project_id || '\u{1F}' || entry_json FROM project_catalog ORDER BY project_id;",
                "SELECT review_id || '\u{1F}' || review_json FROM project_identity_review ORDER BY review_id;",
            ]
            for (table, sql) in optionalTables.sorted(by: { $0.key < $1.key }) {
                var probe: OpaquePointer?
                defer { sqlite3_finalize(probe) }
                guard sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?;", -1, &probe, nil) == SQLITE_OK else { continue }
                sqlite3_bind_text(probe, 1, table, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                if sqlite3_step(probe) == SQLITE_ROW { queries.append(sql) }
            }
            for sql in queries {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw SQLiteArchiveDatabase.StoreError.prepare(String(cString: sqlite3_errmsg(db)))
                }
                while sqlite3_step(statement) == SQLITE_ROW {
                    rows.append(String(cString: sqlite3_column_text(statement, 0)))
                }
            }
            return rows
        }
    }
}
