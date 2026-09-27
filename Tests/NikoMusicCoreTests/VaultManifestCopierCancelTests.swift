import Foundation
import XCTest
@testable import NikoMusicCore

final class VaultManifestCopierCancelTests: XCTestCase {
    func testCopyStopsAfterCancellationAndLeavesSourceIntact() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-copier-cancel-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Audio", isDirectory: true), withIntermediateDirectories: true)
        try Data("cpr".utf8).write(to: source.appendingPathComponent("Song.cpr"))
        try Data(repeating: 0x5a, count: 32).write(to: source.appendingPathComponent("Audio/take.wav"))
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = try VaultManifestBuilder().build(at: source)
        let task = Task {
            try VaultManifestCopier.copy(manifest, from: source, to: destination, fileManager: .default)
        }
        task.cancel()

        do {
            try await task.value
            XCTFail("Canceled copy must throw CancellationError")
        } catch is CancellationError {
            // expected
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("Song.cpr").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("Audio/take.wav").path))
        try VaultManifestBuilder().verify(manifest, at: source)
    }

    func testCancelDuringStagingVerifyLeavesRetryableRecordAndNoPromotedGeneration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-staging-verify-cancel-\(UUID().uuidString)", isDirectory: true)
        let active = root.appendingPathComponent("Active", isDirectory: true)
        let archive = root.appendingPathComponent("Archive", isDirectory: true)
        let source = active.appendingPathComponent("Artist Song", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Audio", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("cubase-project".utf8).write(to: source.appendingPathComponent("Artist Song.cpr"))
        try Data((0..<4096).map { UInt8($0 % 251) }).write(to: source.appendingPathComponent("Audio/take.wav"))
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceManifest = try VaultManifestBuilder().build(at: source)

        let store = try SQLiteVaultTransferStore(databaseURL: root.appendingPathComponent("state/vault.sqlite"))
        let hook = CancelOnHashHook(below: archive)
        let engine = try LocalVaultTransferEngine(
            activeRoot: active,
            archiveRoot: archive,
            store: store,
            faultInjector: { point, _ in
                if point == .verifyingArchiveStaging { hook.arm() }
            },
            writeAdmission: { _, operation in try await operation() },
            manifestBuilder: VaultManifestBuilder(contentHasher: hook.hash)
        )

        // Its own Task: the hook cancels whichever Task is hashing.
        let transfer = Task { try await engine.archive(projectID: ProjectID(), sourceURL: source) }
        do {
            _ = try await transfer.value
            XCTFail("a transfer cancelled during staging verify must throw CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        XCTAssertTrue(hook.cancelled, "the hook must cancel inside the staging verify")
        XCTAssertEqual(hook.hashesAfterCancel, 0, "verify must stop hashing once the transfer is cancelled")
        let persisted = try XCTUnwrap(store.allTransferRecords().first)
        XCTAssertEqual(persisted.state, .failedRecoverable)
        XCTAssertEqual(persisted.error?.origin, .verifyingArchiveStaging)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: persisted.destinationURL.path),
            "no generation may be promoted from an unverified staging copy"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: persisted.stagingURL.path), "staging stays for the retry")
        try VaultManifestBuilder().verify(sourceManifest, at: source)

        hook.disarm()
        let retriedRecord = await engine.retryRecoverableTransfer(id: persisted.id)
        let retried = try XCTUnwrap(retriedRecord)
        XCTAssertEqual(retried.state, .archiveVerified)
        try VaultManifestBuilder().verifyArchive(XCTUnwrap(retried.manifest), at: retried.destinationURL)
        try VaultManifestBuilder().verify(sourceManifest, at: source)
    }

    func testCancelDuringFinalSourceVerifyKeepsActiveAndArchiveVerifiedNotSourceMutated() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-removal-verify-cancel-\(UUID().uuidString)", isDirectory: true)
        let active = root.appendingPathComponent("Active", isDirectory: true)
        let archive = root.appendingPathComponent("Archive", isDirectory: true)
        let source = active.appendingPathComponent("Artist Song", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Audio", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("cubase-project".utf8).write(to: source.appendingPathComponent("Artist Song.cpr"))
        try Data((0..<4096).map { UInt8($0 % 251) }).write(to: source.appendingPathComponent("Audio/take.wav"))
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceManifest = try VaultManifestBuilder().build(at: source)

        let store = try SQLiteVaultTransferStore(databaseURL: root.appendingPathComponent("state/vault.sqlite"))
        let hook = CancelOnHashHook(below: source)
        let engine = try LocalVaultTransferEngine(
            activeRoot: active,
            archiveRoot: archive,
            store: store,
            writeAdmission: { _, operation in try await operation() },
            // Arm after the first evidence check, so the cancel lands inside
            // the final source verify right before the destructive remove.
            removalAdmission: { _ in hook.arm() },
            manifestBuilder: VaultManifestBuilder(contentHasher: hook.hash)
        )
        let verified = try await engine.archive(projectID: ProjectID(), sourceURL: source)

        let removal = Task { try await engine.removeActiveCopy(after: verified) }
        do {
            _ = try await removal.value
            XCTFail("a removal cancelled during the source verify must throw CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        XCTAssertTrue(hook.cancelled, "the hook must cancel inside the final source verify")
        XCTAssertEqual(hook.hashesAfterCancel, 0)
        let persisted = try XCTUnwrap(store.record(id: verified.id))
        XCTAssertEqual(persisted.state, .archiveVerified, "a cancel is not a changed source")
        XCTAssertNotEqual(persisted.error?.reason, .sourceMutated)
        try VaultManifestBuilder().verify(sourceManifest, at: source)
    }
}
