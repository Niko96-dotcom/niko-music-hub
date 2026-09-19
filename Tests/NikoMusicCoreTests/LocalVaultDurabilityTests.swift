import Darwin
import Foundation
import SQLite3
import XCTest
@testable import NikoMusicCore

/// Focused faults for the honest local Vault persistence barrier
/// (`LocalVaultDurabilityBarrier`, `LocalFolderArchiveStorage`, and the
/// `SQLiteArchiveDatabase` durability configuration).
///
/// Scope: fully-local supported filesystems, strict flush failures,
/// containment/symlink/device+inode validation (including deterministic
/// same-device replacement and ancestor faults), cancellation, the promotion
/// ancestor chain, the single terminal drain, and the SQLite
/// configured-vs-verified persistence split, plus a real-temp-fixture syscall
/// acceptance check. This file proves barrier behavior only — never
/// power-loss survival, which no test here can prove
/// (see `docs/vault-durability.md`).
///
/// Covered elsewhere (not re-proven here): interrupted/relaunch recovery
/// (`LocalVaultTransferEngineTests.recoverAtLaunch` paths), provider
/// offline/unsynced/slow-sync faults (`FailingDurabilityProvider`,
/// `PromotionDurabilityProvider`), corrupt-generation rejection
/// (`FinalDurabilityMutatingProvider`), and admission postponements including
/// insufficient capacity (`LocalVaultTransferEngineTests`).
final class LocalVaultDurabilityTests: XCTestCase {
    // MARK: - Fixtures

    private struct Tree {
        let base: URL
        let archiveRoot: URL
        let generation: URL
        let projectDir: URL
        let generationsDir: URL
        let files: [URL]
    }

    private func makeTree(fileNames: [String] = ["Song.cpr", "Audio/take.wav", "Audio/Nested/deep.wav"]) throws -> Tree {
        // Canonicalize up front: `temporaryDirectory` may contain a symlinked
        // ancestor (`/var` -> `/private/var`), while the barrier reports the
        // resolved paths it actually flushed. Deriving every URL from the
        // canonical base keeps fixture paths and barrier reports identical.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-vault-durability-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let archiveRoot = base.appendingPathComponent("Archive", isDirectory: true)
        let generationsDir = archiveRoot.appendingPathComponent("generations", isDirectory: true)
        let projectDir = generationsDir.appendingPathComponent("project", isDirectory: true)
        let generation = projectDir.appendingPathComponent("generation-test", isDirectory: true)
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        var files: [URL] = []
        for name in fileNames {
            let url = generation.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("vault-durability-\(name)".utf8).write(to: url)
            files.append(url)
        }
        return Tree(
            base: base,
            archiveRoot: archiveRoot,
            generation: generation,
            projectDir: projectDir,
            generationsDir: generationsDir,
            files: files
        )
    }

    private func remove(_ tree: Tree) {
        try? FileManager.default.removeItem(at: tree.base)
    }

    private func snapshot(_ urls: [URL]) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for url in urls {
            result[url.path] = try Data(contentsOf: url)
        }
        return result
    }

    // MARK: - Barrier: nested tree ordering and success

    func testNestedTreeFlushesFilesBeforeDirectoriesAndAncestorsLast() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let log = FlushLog()
        let seam = recordingSeam(log: log)
        let barrier = LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: seam)

        XCTAssertEqual(try barrier.makeDurable(at: tree.generation), .verifiedLocal)

        let events = normalizedDurabilityEvents(log.events)
        func index(of event: String) -> Int {
            let normalized = normalizedDurabilityEvent(event)
            XCTAssertNotNil(events.firstIndex(of: normalized), "missing flush event: \(event) in \(events)")
            return events.firstIndex(of: normalized) ?? -1
        }
        // Efficient sequence: fsync every file, then every directory
        // deepest-first, then ancestors inside-out, then exactly one terminal
        // drain on the archive root.
        for file in tree.files {
            XCTAssertTrue(events.contains(durabilitySyncEvent(kind: "sync file", url: file)), "missing sync for \(file.path) in \(events)")
        }
        XCTAssertFalse(events.contains(where: { $0.hasPrefix("drain file ") }), "files must not drain individually: \(events)")
        let lastFileSync = tree.files.map { index(of: "sync file \($0.path)") }.max() ?? -1
        let firstDirSync = [
            index(of: "sync dir \(tree.generation.path)"),
            index(of: "sync dir \(tree.generation.appendingPathComponent("Audio").path)"),
            index(of: "sync dir \(tree.generation.appendingPathComponent("Audio/Nested").path)"),
        ].min() ?? Int.max
        XCTAssertLessThan(lastFileSync, firstDirSync, "files must sync before directories")
        // Directories sync deepest-first.
        let nestedSync = index(of: "sync dir \(tree.generation.appendingPathComponent("Audio/Nested").path)")
        let audioSync = index(of: "sync dir \(tree.generation.appendingPathComponent("Audio").path)")
        let generationSync = index(of: "sync dir \(tree.generation.path)")
        XCTAssertLessThan(nestedSync, audioSync)
        XCTAssertLessThan(audioSync, generationSync)
        // Promotion ancestors sync after the generation, inside-out.
        let projectSync = index(of: "sync dir \(tree.projectDir.path)")
        let generationsSync = index(of: "sync dir \(tree.generationsDir.path)")
        let rootSync = index(of: "sync dir \(tree.archiveRoot.path)")
        XCTAssertLessThan(generationSync, projectSync)
        XCTAssertLessThan(projectSync, generationsSync)
        XCTAssertLessThan(generationsSync, rootSync)
        // Single terminal drain on the archive root after every sync.
        let drains = events.filter { $0.hasPrefix("drain ") }
        XCTAssertEqual(drains, [durabilitySyncEvent(kind: "drain dir", url: tree.archiveRoot)], "exactly one terminal drain on the root: \(events)")
        XCTAssertLessThan(rootSync, index(of: "drain dir \(tree.archiveRoot.path)"))
        // Bytes are untouched by the barrier.
        for file in tree.files {
            let relative = file.path.hasPrefix(tree.generation.path + "/")
                ? String(file.path.dropFirst(tree.generation.path.count + 1))
                : file.lastPathComponent
            XCTAssertEqual(try Data(contentsOf: file), Data("vault-durability-\(relative)".utf8))
        }
    }

    func testEmptyTreeSucceedsFlushingOnlyDirectories() throws {
        let tree = try makeTree(fileNames: [])
        defer { remove(tree) }
        let log = FlushLog()
        let barrier = LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: recordingSeam(log: log))

        XCTAssertEqual(try barrier.makeDurable(at: tree.generation), .verifiedLocal)
        XCTAssertFalse(log.events.isEmpty)
        let normalized = normalizedDurabilityEvents(log.events)
        let drains = normalized.filter { $0.hasPrefix("drain ") }
        XCTAssertEqual(drains, [durabilitySyncEvent(kind: "drain dir", url: tree.archiveRoot)], "empty tree ends with one root drain: \(normalized)")
        XCTAssertTrue(normalized.dropLast().allSatisfy { $0.hasPrefix("sync dir ") }, "empty tree syncs directories only before the drain: \(normalized)")
        XCTAssertTrue(normalized.contains(durabilitySyncEvent(kind: "sync dir", url: tree.generation)))
        XCTAssertTrue(normalized.contains(durabilitySyncEvent(kind: "sync dir", url: tree.archiveRoot)))
    }

    func testGenerationEqualToRootTraversesFullTreeInsteadOfRootOnlyShortcut() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let log = FlushLog()
        let barrier = LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: recordingSeam(log: log))

        XCTAssertEqual(try barrier.makeDurable(at: tree.archiveRoot), .verifiedLocal)
        // The full tree below the root must be synced, not just the root.
        let normalized = normalizedDurabilityEvents(log.events)
        for file in tree.files {
            XCTAssertTrue(normalized.contains(durabilitySyncEvent(kind: "sync file", url: file)), "root generation must sync nested file \(file.path): \(normalized)")
        }
        XCTAssertTrue(normalized.contains(durabilitySyncEvent(kind: "sync dir", url: tree.generation)))
        XCTAssertEqual(normalized.filter { $0.hasPrefix("drain ") }, [durabilitySyncEvent(kind: "drain dir", url: tree.archiveRoot)])
    }

    func testSameDeviceSameTypeFileReplacementFailsClosed() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let victim = try XCTUnwrap(tree.files.first)
        let live = LocalVaultFlushSeam.live
        let realInode = try live.inodeOf(victim)
        // Deterministic same-device same-type replacement: traversal records
        // the fake inode, while the live open+fstat still sees the real one.
        // Fake (not remove-then-rewrite) so the original inode stays
        // allocated and cannot be reused flakily; path matching is normalized
        // for the `/var` vs `/private/var` spelling split so the fault fires.
        let seam = LocalVaultFlushSeam(
            deviceIDOf: live.deviceIDOf,
            inodeOf: { url in durabilityTestURLsMatch(url, victim) ? realInode &+ 1 : try live.inodeOf(url) },
            filesystemTypeOf: live.filesystemTypeOf,
            filesystemTypeOfDescriptor: live.filesystemTypeOfDescriptor,
            synchronize: live.synchronize,
            drainDeviceQueue: live.drainDeviceQueue,
            checkCancellation: live.checkCancellation
        )
        let before = try snapshot(tree.files)

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: seam).makeDurable(at: tree.generation)
            XCTFail("same-device same-type replacement must fail closed")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .deviceMismatch(let actual) = error, durabilityTestURLsMatch(actual, victim) else {
                XCTFail("expected deviceMismatch \(victim.path), got \(error)")
                return
            }
        }
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    func testAncestorReplacementFailsClosed() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let live = LocalVaultFlushSeam.live
        let realInode = try live.inodeOf(tree.projectDir)
        let seam = LocalVaultFlushSeam(
            deviceIDOf: live.deviceIDOf,
            inodeOf: { url in durabilityTestURLsMatch(url, tree.projectDir) ? realInode &+ 1 : try live.inodeOf(url) },
            filesystemTypeOf: live.filesystemTypeOf,
            filesystemTypeOfDescriptor: live.filesystemTypeOfDescriptor,
            synchronize: live.synchronize,
            drainDeviceQueue: live.drainDeviceQueue,
            checkCancellation: live.checkCancellation
        )
        let before = try snapshot(tree.files)

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: seam).makeDurable(at: tree.generation)
            XCTFail("ancestor replacement must fail closed")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .deviceMismatch(let actual) = error, durabilityTestURLsMatch(actual, tree.projectDir) else {
                XCTFail("expected deviceMismatch \(tree.projectDir.path), got \(error)")
                return
            }
        }
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    func testAncestorSymlinkTraversalFailsClosed() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        // Replace the `project` ancestor with a symlink to a real directory
        // elsewhere under the temp base: the generation path then traverses a
        // symlink, which must fail closed before any flush.
        let relocated = tree.base.appendingPathComponent("relocated-project", isDirectory: true)
        try FileManager.default.moveItem(at: tree.projectDir, to: relocated)
        try FileManager.default.createSymbolicLink(at: tree.projectDir, withDestinationURL: relocated)
        let before = try snapshot(tree.files)

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot).makeDurable(at: tree.generation)
            XCTFail("ancestor symlink traversal must fail closed")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .locationOutsideArchiveRoot(let actual) = error, durabilityTestURLsMatch(actual, tree.generation) else {
                XCTFail("expected locationOutsideArchiveRoot \(tree.generation.path), got \(error)")
                return
            }
        }
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    func testSingleTerminalDrainAfterAllSyncsAndSyncFailureSkipsDrain() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        // Success: exactly one drain, on the root, after every sync.
        let successLog = FlushLog()
        XCTAssertEqual(
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: recordingSeam(log: successLog)).makeDurable(at: tree.generation),
            .verifiedLocal
        )
        let successNormalized = normalizedDurabilityEvents(successLog.events)
        let successDrains = successNormalized.filter { $0.hasPrefix("drain ") }
        XCTAssertEqual(successDrains, [durabilitySyncEvent(kind: "drain dir", url: tree.archiveRoot)])
        let lastSync = successNormalized.lastIndex(where: { $0.hasPrefix("sync ") }) ?? -1
        let drainIndex = successNormalized.firstIndex(of: durabilitySyncEvent(kind: "drain dir", url: tree.archiveRoot)) ?? Int.max
        XCTAssertLessThan(lastSync, drainIndex)

        // File sync failure: no terminal drain, fail-closed with bytes kept.
        let victim = try XCTUnwrap(tree.files.first)
        let failureLog = FlushLog()
        let live = LocalVaultFlushSeam.live
        let failingSeam = LocalVaultFlushSeam(
            deviceIDOf: live.deviceIDOf,
            inodeOf: live.inodeOf,
            filesystemTypeOf: live.filesystemTypeOf,
            filesystemTypeOfDescriptor: live.filesystemTypeOfDescriptor,
            synchronize: { _, url, isDirectory in
                failureLog.append("sync \(isDirectory ? "dir" : "file") \(url.path)")
                if durabilityTestURLsMatch(url, victim) {
                    throw LocalVaultDurabilityBarrierError.fileFlushFailed(url, errno: EIO)
                }
            },
            drainDeviceQueue: { _, url, isDirectory in failureLog.append("drain \(isDirectory ? "dir" : "file") \(url.path)") },
            checkCancellation: live.checkCancellation
        )
        let before = try snapshot(tree.files)
        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: failingSeam).makeDurable(at: tree.generation)
            XCTFail("file sync failure must not claim durability")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .fileFlushFailed(let actual, let errno) = error, durabilityTestURLsMatch(actual, victim), errno == EIO else {
                XCTFail("expected fileFlushFailed \(victim.path) EIO, got \(error)")
                return
            }
        }
        XCTAssertFalse(failureLog.events.contains(where: { $0.hasPrefix("drain ") }), "failed sync must skip the terminal drain")
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }


    // MARK: - Barrier: containment and symlink escapes

    func testFileSymlinkEscapeFailsClosedPreservingBytes() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let outside = tree.base.appendingPathComponent("outside.dat")
        try Data("outside".utf8).write(to: outside)
        let link = tree.generation.appendingPathComponent("Audio/escape-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let before = try snapshot(tree.files)

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot).makeDurable(at: tree.generation)
            XCTFail("symlink escape must fail closed")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .symlinkEscape(let actual) = error, durabilityTestURLsMatch(actual, link) else {
                XCTFail("expected symlinkEscape \(link.path), got \(error)")
                return
            }
        }
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
        XCTAssertEqual(try Data(contentsOf: outside), Data("outside".utf8))
    }

    func testDirectorySymlinkEscapeFailsClosedPreservingBytes() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let outsideDir = tree.base.appendingPathComponent("outside-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outsideDir.appendingPathComponent("stash.dat"))
        let link = tree.generation.appendingPathComponent("linked-dir")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideDir)
        let before = try snapshot(tree.files)

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot).makeDurable(at: tree.generation)
            XCTFail("directory symlink escape must fail closed")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .symlinkEscape(let actual) = error, durabilityTestURLsMatch(actual, link) else {
                XCTFail("expected symlinkEscape \(link.path), got \(error)")
                return
            }
        }
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    func testLocationOutsideArchiveRootFailsClosed() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let elsewhere = tree.base.appendingPathComponent("Elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data("stray".utf8).write(to: elsewhere.appendingPathComponent("stray.dat"))

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot).makeDurable(at: elsewhere)
            XCTFail("out-of-root location must fail closed")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .locationOutsideArchiveRoot(let actual) = error, durabilityTestURLsMatch(actual, elsewhere) else {
                XCTFail("expected locationOutsideArchiveRoot \(elsewhere.path), got \(error)")
                return
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("stray.dat").path))
    }

    // MARK: - Barrier: unsupported filesystem and device mismatch

    func testUnsupportedFilesystemFailsClosedWithClearReason() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let live = LocalVaultFlushSeam.live
        let seam = LocalVaultFlushSeam(
            deviceIDOf: live.deviceIDOf,
            inodeOf: live.inodeOf,
            filesystemTypeOf: { _ in "nfs" },
            filesystemTypeOfDescriptor: live.filesystemTypeOfDescriptor,
            synchronize: live.synchronize,
            drainDeviceQueue: live.drainDeviceQueue,
            checkCancellation: live.checkCancellation
        )
        let before = try snapshot(tree.files)

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: seam).makeDurable(at: tree.generation)
            XCTFail("unsupported filesystem must fail closed")
        } catch let error as LocalVaultDurabilityBarrierError {
            XCTAssertEqual(error, .unsupportedFilesystem("nfs"))
            XCTAssertTrue(error.errorDescription?.contains("nfs") == true, "blocked reason must name the filesystem")
            XCTAssertTrue(error.errorDescription?.contains("kept") == true, "blocked reason must state bytes were kept")
        }
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    func testDeviceMismatchFailsClosedPreservingBytes() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let live = LocalVaultFlushSeam.live
        let rootDevice = try live.deviceIDOf(tree.archiveRoot)
        let victim = try XCTUnwrap(tree.files.first)
        let seam = LocalVaultFlushSeam(
            deviceIDOf: { url in durabilityTestURLsMatch(url, victim) ? rootDevice &+ 1 : try live.deviceIDOf(url) },
            inodeOf: live.inodeOf,
            filesystemTypeOf: live.filesystemTypeOf,
            filesystemTypeOfDescriptor: live.filesystemTypeOfDescriptor,
            synchronize: live.synchronize,
            drainDeviceQueue: live.drainDeviceQueue,
            checkCancellation: live.checkCancellation
        )
        let before = try snapshot(tree.files)

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: seam).makeDurable(at: tree.generation)
            XCTFail("device mismatch must fail closed")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .deviceMismatch(let actual) = error, durabilityTestURLsMatch(actual, victim) else {
                XCTFail("expected deviceMismatch \(victim.path), got \(error)")
                return
            }
        }
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    // MARK: - Barrier: flush failures never downgrade

    func testFileFlushFailureNeverClaimsDurability() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let victim = try XCTUnwrap(tree.files.first)
        let log = FlushLog()
        let live = LocalVaultFlushSeam.live
        let seam = LocalVaultFlushSeam(
            deviceIDOf: live.deviceIDOf,
            inodeOf: live.inodeOf,
            filesystemTypeOf: live.filesystemTypeOf,
            filesystemTypeOfDescriptor: live.filesystemTypeOfDescriptor,
            synchronize: { _, url, isDirectory in
                log.append("sync \(isDirectory ? "dir" : "file") \(url.path)")
                if durabilityTestURLsMatch(url, victim) {
                    throw LocalVaultDurabilityBarrierError.fileFlushFailed(url, errno: EIO)
                }
            },
            drainDeviceQueue: { _, url, isDirectory in log.append("drain \(isDirectory ? "dir" : "file") \(url.path)") },
            checkCancellation: live.checkCancellation
        )
        let before = try snapshot(tree.files)

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: seam).makeDurable(at: tree.generation)
            XCTFail("file flush failure must not claim durability")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .fileFlushFailed(let actual, let errno) = error, durabilityTestURLsMatch(actual, victim), errno == EIO else {
                XCTFail("expected fileFlushFailed \(victim.path) EIO, got \(error)")
                return
            }
        }
        XCTAssertFalse(log.events.contains(where: { $0.hasPrefix("drain ") }), "failed file must not reach the terminal drain phase")
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    func testFullSyncFailureIsNotDowngradedToPlainSyncSuccess() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let live = LocalVaultFlushSeam.live
        let seam = LocalVaultFlushSeam(
            deviceIDOf: live.deviceIDOf,
            inodeOf: live.inodeOf,
            filesystemTypeOf: live.filesystemTypeOf,
            filesystemTypeOfDescriptor: live.filesystemTypeOfDescriptor,
            synchronize: live.synchronize,
            drainDeviceQueue: { _, url, _ in
                // Every fsync already succeeded; the single terminal drain on
                // the archive root must still refuse durability rather than
                // downgrade to plain-sync success.
                throw LocalVaultDurabilityBarrierError.fullSyncFailed(url, errno: EIO)
            },
            checkCancellation: live.checkCancellation
        )
        let before = try snapshot(tree.files)

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: seam).makeDurable(at: tree.generation)
            XCTFail("full-sync failure must not be downgraded to plain-sync success")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .fullSyncFailed(let actual, let errno) = error, durabilityTestURLsMatch(actual, tree.archiveRoot), errno == EIO else {
                XCTFail("expected fullSyncFailed \(tree.archiveRoot.path) EIO, got \(error)")
                return
            }
        }
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    func testFilesystemTypeDriftAtDrainFailsClosedAsUnsupported() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let live = LocalVaultFlushSeam.live
        let drainLog = FlushLog()
        // Start-of-run qualification sees a supported volume, but the drain
        // descriptor itself reports an unqualified type: the terminal drain
        // must fail closed with `unsupportedFilesystem`, never
        // `.verifiedLocal`, and must not run the device drain.
        let seam = LocalVaultFlushSeam(
            deviceIDOf: live.deviceIDOf,
            inodeOf: live.inodeOf,
            filesystemTypeOf: { _ in "apfs" },
            filesystemTypeOfDescriptor: { _, _ in "exfat" },
            synchronize: live.synchronize,
            drainDeviceQueue: { _, url, isDirectory in drainLog.append("drain \(isDirectory ? "dir" : "file") \(url.path)") },
            checkCancellation: live.checkCancellation
        )
        let before = try snapshot(tree.files)

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: seam).makeDurable(at: tree.generation)
            XCTFail("filesystem drift at drain must fail closed")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .unsupportedFilesystem(let name) = error, name == "exfat" else {
                XCTFail("expected unsupportedFilesystem exfat at drain, got \(error)")
                return
            }
        }
        XCTAssertTrue(drainLog.events.isEmpty, "drifted drain must not run the device drain")
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    func testTmpUserSpellingConfinesWithoutAcceptingNestedSymlinks() throws {
        // Legitimate `/tmp` user spelling: `/tmp` is a symlink to
        // `/private/tmp`, so the unresolved spelling must still confine while
        // nested symlinks keep failing closed (covered by the symlink-escape
        // tests above; this test pins the spelling acceptance).
        let token = UUID().uuidString
        let archiveRoot = URL(fileURLWithPath: "/tmp/local-vault-durability-alias-\(token)/Archive", isDirectory: true)
        let generation = archiveRoot.appendingPathComponent("generations/project/generation-test", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: archiveRoot) }
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let file = generation.appendingPathComponent("Song.cpr")
        try Data("vault-durability-alias".utf8).write(to: file)

        XCTAssertEqual(
            try LocalVaultDurabilityBarrier(archiveRoot: archiveRoot, seam: .live).makeDurable(at: generation),
            .verifiedLocal,
            "legitimate /tmp spelling must confine and prove"
        )
        XCTAssertEqual(try Data(contentsOf: file), Data("vault-durability-alias".utf8))

        // Narrowness: a nested symlink under the same spelling still fails.
        let outside = URL(fileURLWithPath: "/tmp/local-vault-durability-alias-\(token)-outside.dat")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("outside".utf8).write(to: outside)
        let link = generation.appendingPathComponent("escape-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        do {
            try LocalVaultDurabilityBarrier(archiveRoot: archiveRoot, seam: .live).makeDurable(at: generation)
            XCTFail("nested symlink under an aliased root must still fail closed")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .symlinkEscape = error else {
                XCTFail("expected symlinkEscape under aliased root, got \(error)")
                return
            }
        }
        try FileManager.default.removeItem(at: link)
    }

    func testDirectoryFlushFailureNeverClaimsDurability() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let live = LocalVaultFlushSeam.live
        let seam = LocalVaultFlushSeam(
            deviceIDOf: live.deviceIDOf,
            inodeOf: live.inodeOf,
            filesystemTypeOf: live.filesystemTypeOf,
            filesystemTypeOfDescriptor: live.filesystemTypeOfDescriptor,
            synchronize: { _, url, isDirectory in
                if isDirectory, durabilityTestURLsMatch(url, tree.generation) {
                    throw LocalVaultDurabilityBarrierError.directoryFlushFailed(url, errno: EIO)
                }
            },
            drainDeviceQueue: live.drainDeviceQueue,
            checkCancellation: live.checkCancellation
        )
        let before = try snapshot(tree.files)

        do {
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: seam).makeDurable(at: tree.generation)
            XCTFail("directory flush failure must not claim durability")
        } catch let error as LocalVaultDurabilityBarrierError {
            guard case .directoryFlushFailed(let actual, let errno) = error, durabilityTestURLsMatch(actual, tree.generation), errno == EIO else {
                XCTFail("expected directoryFlushFailed \(tree.generation.path) EIO, got \(error)")
                return
            }
        }
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    // MARK: - Barrier: cancellation

    func testCancelledBarrierPropagatesCancellationWithoutClaimingDurability() throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let live = LocalVaultFlushSeam.live
        let canceller = CancellationCounter(limit: 2)
        let seam = LocalVaultFlushSeam(
            deviceIDOf: live.deviceIDOf,
            inodeOf: live.inodeOf,
            filesystemTypeOf: live.filesystemTypeOf,
            filesystemTypeOfDescriptor: live.filesystemTypeOfDescriptor,
            synchronize: live.synchronize,
            drainDeviceQueue: live.drainDeviceQueue,
            checkCancellation: { try canceller.check() }
        )
        let before = try snapshot(tree.files)

        XCTAssertThrowsError(try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: seam).makeDurable(at: tree.generation)) { error in
            XCTAssertTrue(error is CancellationError, "cancellation must propagate unwrapped, got \(error)")
        }
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    // MARK: - Barrier: real temp fixture syscall acceptance

    /// Live syscalls against a real local temp fixture: every descriptor
    /// accepts `fsync` and `F_FULLFSYNC`. This is syscall acceptance only —
    /// not a power-cut test and not an external filesystem guarantee.
    func testRealTempFixtureAcceptsFullFlushSequence() throws {
        let tree = try makeTree()
        defer { remove(tree) }

        XCTAssertEqual(
            try LocalVaultDurabilityBarrier(archiveRoot: tree.archiveRoot, seam: .live).makeDurable(at: tree.generation),
            .verifiedLocal
        )
        for file in tree.files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
    }

    // MARK: - Provider: no verifiedLocal merely because copy returned

    func testLocalFolderProviderRunsBarrierBeforeClaimingVerifiedLocal() async throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let storage = LocalFolderArchiveStorage(root: tree.archiveRoot)

        let durability = try await storage.waitUntilDurable(tree.generation)
        XCTAssertEqual(durability, .verifiedLocal)
        XCTAssertEqual(try snapshot(tree.files).count, tree.files.count)
    }

    func testLocalFolderProviderBarrierFailureThrowsPreservingBytes() async throws {
        let tree = try makeTree()
        defer { remove(tree) }
        let live = LocalVaultFlushSeam.live
        let failingSeam = LocalVaultFlushSeam(
            deviceIDOf: live.deviceIDOf,
            inodeOf: live.inodeOf,
            filesystemTypeOf: live.filesystemTypeOf,
            filesystemTypeOfDescriptor: live.filesystemTypeOfDescriptor,
            synchronize: live.synchronize,
            drainDeviceQueue: { descriptor, url, isDirectory in
                _ = descriptor
                _ = isDirectory
                throw LocalVaultDurabilityBarrierError.fullSyncFailed(url, errno: EIO)
            },
            checkCancellation: live.checkCancellation
        )
        let storage = LocalFolderArchiveStorage(root: tree.archiveRoot, fileManager: .default, flushSeam: failingSeam)
        let before = try snapshot(tree.files)

        do {
            _ = try await storage.waitUntilDurable(tree.generation)
            XCTFail("barrier failure must throw instead of claiming verifiedLocal")
        } catch let error as LocalVaultDurabilityBarrierError {
            // The single terminal drain runs on the archive root after all
            // fsyncs, so a drain fault reports the root, not the first file.
            guard case .fullSyncFailed(let actual, let errno) = error, durabilityTestURLsMatch(actual, tree.archiveRoot), errno == EIO else {
                XCTFail("expected fullSyncFailed \(tree.archiveRoot.path) EIO, got \(error)")
                return
            }
        }
        XCTAssertEqual(try snapshot(tree.files), before, "recoverable bytes must be preserved")
    }

    // MARK: - SQLite: transfer state is recovery evidence

    func testArchiveDatabaseConfiguresFullSyncWithoutMandatoryProofAtOpen() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-vault-durability-db-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("archive-index.sqlite")

        // Open stays readable: no directory/file sync is enforced here, so a
        // volume that cannot prove persistence still exposes recovery records.
        // Proof is explicit via `proveRecoveryPersistence()` before destructive
        // admission. Ancestors above the immediate parent (including a
        // pre-existing storage folder's parents) are an external assumption.
        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        XCTAssertEqual(try pragmaString(database, "PRAGMA journal_mode;").lowercased(), "wal")
        XCTAssertEqual(try pragmaInt(database, "PRAGMA synchronous;"), 2, "synchronous must read back FULL")
        let fullSync = try pragmaInt(database, "PRAGMA fullfsync;")
        XCTAssertTrue(fullSync == 0 || fullSync == 1, "fullfsync read-back must round-trip, got \(fullSync)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path), "database file must exist after init")

        // Per-connection settings must survive reopen: recovery evidence
        // written by a later process launch gets the same configuration.
        let reopened = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        XCTAssertEqual(try pragmaInt(reopened, "PRAGMA synchronous;"), 2)
    }

    func testConfiguredDurabilityIsSeparateFromVerifiedPersistence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-vault-durability-separate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("archive-index.sqlite")
        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)

        // Configuration evidence: synchronous FULL is enforced at open;
        // fullfsync is requested and observed but never proof of enforcement.
        let configured = try database.configuredDurability()
        XCTAssertEqual(configured.synchronous, 2)
        XCTAssertTrue(configured.fullSync == 0 || configured.fullSync == 1)

        // Verified persistence: the strict explicit barrier (strict TRUNCATE
        // checkpoint with busy-row verification and connection-path binding,
        // then DB file + WAL sidecar, then immediate parent directory)
        // succeeds on a writable volume and preserves readable recovery
        // records. Read-back alone never proves syscall completion, so
        // destructive admission must call this barrier.
        let store = try SQLiteVaultTransferStore(database: database)
        let record = VaultTransferRecord(
            projectID: ProjectID(),
            sourceURL: root.appendingPathComponent("active/project"),
            stagingURL: root.appendingPathComponent("archive/.niko-staging/project"),
            destinationURL: root.appendingPathComponent("archive/generations/project"),
            state: .awaitingProviderDurability,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        try store.save(record)
        XCTAssertNoThrow(try database.proveRecoveryPersistence(), "explicit recovery barrier must succeed on a writable volume")
        XCTAssertEqual(try store.record(id: record.id), record, "barrier must preserve recovery evidence")

        // Read-only catalog access stays available even when persistence is
        // unproven: opening the same database still succeeds for reads.
        let reopened = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.configuredDurability().synchronous, 2)
        XCTAssertNoThrow(try reopened.proveRecoveryPersistence())
    }

    func testRecoveryPersistenceJournalSyncFailureFailsClosedPreservingRecords() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-vault-durability-journal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("archive-index.sqlite")
        let liveDatabase = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let store = try SQLiteVaultTransferStore(database: liveDatabase)
        let record = VaultTransferRecord(
            projectID: ProjectID(),
            sourceURL: root.appendingPathComponent("active/project"),
            stagingURL: root.appendingPathComponent("archive/.niko-staging/project"),
            destinationURL: root.appendingPathComponent("archive/generations/project"),
            state: .awaitingProviderDurability,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        try store.save(record)
        // Scoped seam: fail the journal/file sync deterministically so the
        // engine consumer can prove fail-closed handling without touching real
        // volumes. Failing every file sync covers both the DB file and the
        // `-wal` sidecar path when present.
        let liveSeam = SQLiteArchiveDatabase.SQLiteRecoverySyncSeam.live
        let failingSeam = SQLiteArchiveDatabase.SQLiteRecoverySyncSeam(
            checkpointMainDatabase: liveSeam.checkpointMainDatabase,
            synchronizeFile: { url, _ in
                throw SQLiteArchiveDatabase.StoreError.exec("injected journal sync failure for \(url.lastPathComponent)")
            },
            synchronizeDirectory: liveSeam.synchronizeDirectory
        )
        let failingDatabase = try SQLiteArchiveDatabase(databaseURL: databaseURL, recoverySeam: failingSeam)
        do {
            try failingDatabase.proveRecoveryPersistence()
            XCTFail("journal sync failure must fail closed, not claim proof")
        } catch {
            // Any exec failure here is the injected barrier refusal; bytes stay.
            XCTAssertTrue("\(error)".contains("injected journal sync failure"), "must surface the injected journal fault, got \(error)")
        }
        XCTAssertEqual(try store.record(id: record.id), record, "failed proof must preserve recovery evidence")
        // Live barrier still succeeds on the writable volume.
        XCTAssertNoThrow(try liveDatabase.proveRecoveryPersistence())
    }

    func testRecoveryPersistenceRejectsSamePathReplacementWithDifferentFixture() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-vault-durability-replacement-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("archive-index.sqlite")
        let database = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let store = try SQLiteVaultTransferStore(database: database)
        let record = VaultTransferRecord(
            projectID: ProjectID(),
            sourceURL: root.appendingPathComponent("active/project"),
            stagingURL: root.appendingPathComponent("archive/.niko-staging/project"),
            destinationURL: root.appendingPathComponent("archive/generations/project"),
            state: .awaitingProviderDurability,
            createdAt: Date(timeIntervalSince1970: 400)
        )
        try store.save(record)
        XCTAssertNoThrow(try database.proveRecoveryPersistence(), "normal connection must prove before replacement")
        // Independent known original evidence before replacement: the
        // pre-replacement checkpoint above flushed frames into the main file,
        // so copying the main file preserves a readable retained location.
        // This copy (not the live connection, whose pathname is about to be
        // replaced) is the meaningful preservation claim.
        let preservedURL = root.appendingPathComponent("preserved-original.sqlite")
        try FileManager.default.copyItem(at: databaseURL, to: preservedURL)
        let preservedPrecheck = try SQLiteVaultTransferStore(database: SQLiteArchiveDatabase(databaseURL: preservedURL))
        XCTAssertEqual(try preservedPrecheck.record(id: record.id), record, "preservation source must carry original evidence before replacement")

        // Different valid SQLite fixture at a scratch path: same-path
        // replacement keeps `sqlite3_db_filename` identical while the live
        // connection keeps the original inode open.
        let fixtureURL = root.appendingPathComponent("replacement.sqlite")
        try makeReplacementSQLiteFixture(at: fixtureURL, marker: "replacement-same-path")
        try replaceSQLiteFileAtPath(databaseURL, withFixture: fixtureURL)

        do {
            try database.proveRecoveryPersistence()
            XCTFail("same-path replacement with a different fixture must fail closed")
        } catch {
            let message = "\(error)"
            XCTAssertTrue(
                message.contains("replaced") || message.contains("identity") || message.contains("moved") || message.contains("changed") || message.contains("binding"),
                "must report replacement identity, got \(error)"
            )
        }
        // Failed proof must preserve recovery evidence at the retained
        // location: the pre-replacement copy stays readable. The live
        // connection's pathname now names the replacement, so it cannot serve
        // as the preservation claim.
        let preservedDatabase = try SQLiteArchiveDatabase(databaseURL: preservedURL)
        let preservedStore = try SQLiteVaultTransferStore(database: preservedDatabase)
        XCTAssertEqual(try preservedStore.record(id: record.id), record, "failed proof must preserve recovery evidence at the retained location")

        // Reopening binds to the replacement file: a fresh connection proves
        // with its own binding and sees the replacement content.
        let reopened = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        XCTAssertNoThrow(try reopened.proveRecoveryPersistence(), "reopened connection to the replacement must prove with a fresh binding")
        XCTAssertEqual(try replacementMarker(on: reopened), "replacement-same-path", "reopened connection must see the replacement fixture")
    }

    func testRecoveryPersistenceRejectsMutationDuringInjectedCheckpoint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-vault-durability-checkpoint-mutation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("archive-index.sqlite")
        let liveDatabase = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let store = try SQLiteVaultTransferStore(database: liveDatabase)
        let record = VaultTransferRecord(
            projectID: ProjectID(),
            sourceURL: root.appendingPathComponent("active/project"),
            stagingURL: root.appendingPathComponent("archive/.niko-staging/project"),
            destinationURL: root.appendingPathComponent("archive/generations/project"),
            state: .awaitingProviderDurability,
            createdAt: Date(timeIntervalSince1970: 500)
        )
        try store.save(record)
        XCTAssertNoThrow(try liveDatabase.proveRecoveryPersistence(), "live connection must checkpoint before preservation")
        // Independent known original evidence before the injected mutation:
        // checkpointed main file copied to a safe relocated fixture.
        let preservedURL = root.appendingPathComponent("preserved-original.sqlite")
        try FileManager.default.copyItem(at: databaseURL, to: preservedURL)
        let preservedPrecheck = try SQLiteVaultTransferStore(database: SQLiteArchiveDatabase(databaseURL: preservedURL))
        XCTAssertEqual(try preservedPrecheck.record(id: record.id), record, "preservation source must carry original evidence before mutation")
        let fixtureURL = root.appendingPathComponent("replacement.sqlite")
        try makeReplacementSQLiteFixture(at: fixtureURL, marker: "replacement-checkpoint")

        let liveSeam = SQLiteArchiveDatabase.SQLiteRecoverySyncSeam.live
        let checkpointTarget = databaseURL
        let checkpointFixture = fixtureURL
        let checkpointLive = liveSeam.checkpointMainDatabase
        let mutatingSeam = SQLiteArchiveDatabase.SQLiteRecoverySyncSeam(
            checkpointMainDatabase: { db in
                // Targeted post-checkpoint identity recheck: checkpoint the
                // live connection first, then swap the pathname to an
                // unrelated valid fixture before the seam returns. The
                // post-checkpoint binding recheck must reject. (If SQLite
                // surfaces a disk I/O error during the checkpoint itself,
                // that IO refusal already fails closed.)
                try checkpointLive(db)
                try? FileManager.default.removeItem(atPath: checkpointTarget.path + "-wal")
                try? FileManager.default.removeItem(atPath: checkpointTarget.path + "-shm")
                try FileManager.default.removeItem(at: checkpointTarget)
                try FileManager.default.copyItem(at: checkpointFixture, to: checkpointTarget)
            },
            synchronizeFile: liveSeam.synchronizeFile,
            synchronizeDirectory: liveSeam.synchronizeDirectory
        )
        let mutatingDatabase = try SQLiteArchiveDatabase(databaseURL: databaseURL, recoverySeam: mutatingSeam)
        do {
            try mutatingDatabase.proveRecoveryPersistence()
            XCTFail("replacement during checkpoint must fail closed")
        } catch {
            let message = "\(error)"
            let reportsIdentity = message.contains("replaced") || message.contains("identity") || message.contains("moved") || message.contains("changed") || message.contains("binding")
            let reportsIORefusal = message.lowercased().contains("disk i/o") || message.lowercased().contains("i/o error") || message.lowercased().contains("io error")
            XCTAssertTrue(reportsIdentity || reportsIORefusal, "must fail closed on checkpoint mutation (identity rejection or IO refusal), got \(error)")
        }
        // Failed proof must preserve recovery evidence at the retained
        // location (safe relocated copy), not via the mutated pathname.
        let preservedDatabase = try SQLiteArchiveDatabase(databaseURL: preservedURL)
        let preservedStore = try SQLiteVaultTransferStore(database: preservedDatabase)
        XCTAssertEqual(try preservedStore.record(id: record.id), record, "failed proof must preserve recovery evidence")
        // Fault must actually fire: the mutated pathname now names the
        // replacement fixture.
        let reopened = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        XCTAssertEqual(try replacementMarker(on: reopened), "replacement-checkpoint", "injected checkpoint mutation must actually replace the pathname")
    }

    func testRecoveryPersistenceRejectsMutationDuringInjectedFileSync() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-vault-durability-sync-mutation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("archive-index.sqlite")
        let liveDatabase = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let store = try SQLiteVaultTransferStore(database: liveDatabase)
        let record = VaultTransferRecord(
            projectID: ProjectID(),
            sourceURL: root.appendingPathComponent("active/project"),
            stagingURL: root.appendingPathComponent("archive/.niko-staging/project"),
            destinationURL: root.appendingPathComponent("archive/generations/project"),
            state: .awaitingProviderDurability,
            createdAt: Date(timeIntervalSince1970: 600)
        )
        try store.save(record)
        XCTAssertNoThrow(try liveDatabase.proveRecoveryPersistence(), "live connection must checkpoint before preservation")
        // Independent known original evidence before the injected mutation.
        let preservedURL = root.appendingPathComponent("preserved-original.sqlite")
        try FileManager.default.copyItem(at: databaseURL, to: preservedURL)
        let preservedPrecheck = try SQLiteVaultTransferStore(database: SQLiteArchiveDatabase(databaseURL: preservedURL))
        XCTAssertEqual(try preservedPrecheck.record(id: record.id), record, "preservation source must carry original evidence before mutation")
        let fixtureURL = root.appendingPathComponent("replacement.sqlite")
        try makeReplacementSQLiteFixture(at: fixtureURL, marker: "replacement-sync")

        let liveSeam = SQLiteArchiveDatabase.SQLiteRecoverySyncSeam.live
        let syncTarget = databaseURL
        let syncFixture = fixtureURL
        let syncLiveFile = liveSeam.synchronizeFile
        let mutatingSeam = SQLiteArchiveDatabase.SQLiteRecoverySyncSeam(
            checkpointMainDatabase: liveSeam.checkpointMainDatabase,
            synchronizeFile: { url, bound in
                // Concurrent replacement during the file flush: swap the main
                // database pathname before syncing, so the sync would flush
                // the unrelated replacement. The descriptor-bound sync must
                // refuse BEFORE flushing (not merely recheck the path after),
                // and the post-sync binding recheck also rejects.
                if url.standardizedFileURL.path == syncTarget.standardizedFileURL.path {
                    try? FileManager.default.removeItem(atPath: syncTarget.path + "-wal")
                    try? FileManager.default.removeItem(atPath: syncTarget.path + "-shm")
                    try FileManager.default.removeItem(at: syncTarget)
                    try FileManager.default.copyItem(at: syncFixture, to: syncTarget)
                }
                try syncLiveFile(url, bound)
            },
            synchronizeDirectory: liveSeam.synchronizeDirectory
        )
        let mutatingDatabase = try SQLiteArchiveDatabase(databaseURL: databaseURL, recoverySeam: mutatingSeam)
        do {
            try mutatingDatabase.proveRecoveryPersistence()
            XCTFail("replacement during file sync must fail closed")
        } catch {
            let message = "\(error)"
            XCTAssertTrue(
                message.contains("replaced") || message.contains("identity") || message.contains("moved") || message.contains("changed") || message.contains("binding"),
                "must report sync-mutation identity, got \(error)"
            )
        }
        // Failed proof must preserve recovery evidence at the retained
        // location (safe relocated copy), not via the mutated pathname.
        let preservedDatabase = try SQLiteArchiveDatabase(databaseURL: preservedURL)
        let preservedStore = try SQLiteVaultTransferStore(database: preservedDatabase)
        XCTAssertEqual(try preservedStore.record(id: record.id), record, "failed proof must preserve recovery evidence")
        // Fault must actually fire: the mutated pathname now names the
        // replacement fixture.
        let reopened = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        XCTAssertEqual(try replacementMarker(on: reopened), "replacement-sync", "injected sync mutation must actually replace the pathname")
    }

    func testRecoveryPersistenceRejectsReplacementThenRestoreDuringFileSync() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-vault-durability-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("archive-index.sqlite")
        let liveDatabase = try SQLiteArchiveDatabase(databaseURL: databaseURL)
        let store = try SQLiteVaultTransferStore(database: liveDatabase)
        let record = VaultTransferRecord(
            projectID: ProjectID(),
            sourceURL: root.appendingPathComponent("active/project"),
            stagingURL: root.appendingPathComponent("archive/.niko-staging/project"),
            destinationURL: root.appendingPathComponent("archive/generations/project"),
            state: .awaitingProviderDurability,
            createdAt: Date(timeIntervalSince1970: 650)
        )
        try store.save(record)
        XCTAssertNoThrow(try liveDatabase.proveRecoveryPersistence(), "live connection must checkpoint before preservation")
        let preservedURL = root.appendingPathComponent("preserved-original.sqlite")
        try FileManager.default.copyItem(at: databaseURL, to: preservedURL)
        let preservedPrecheck = try SQLiteVaultTransferStore(database: SQLiteArchiveDatabase(databaseURL: preservedURL))
        XCTAssertEqual(try preservedPrecheck.record(id: record.id), record, "preservation source must carry original evidence before mutation")
        let fixtureURL = root.appendingPathComponent("replacement.sqlite")
        try makeReplacementSQLiteFixture(at: fixtureURL, marker: "replacement-restore")

        // Replacement-then-restore: move the original aside (inode preserved),
        // flush the replacement at the same path, then move the original back
        // before the seam returns. A path-only post-check would see the
        // original identity again (plus an unmoved connection) and falsely
        // prove; the descriptor-bound sync must refuse the replacement BEFORE
        // flushing it.
        let liveSeam = SQLiteArchiveDatabase.SQLiteRecoverySyncSeam.live
        let syncTarget = databaseURL
        let syncFixture = fixtureURL
        let syncLiveFile = liveSeam.synchronizeFile
        let stashURL = root.appendingPathComponent("stashed-original.sqlite")
        let restoreSeam = SQLiteArchiveDatabase.SQLiteRecoverySyncSeam(
            checkpointMainDatabase: liveSeam.checkpointMainDatabase,
            synchronizeFile: { url, bound in
                guard url.standardizedFileURL.path == syncTarget.standardizedFileURL.path else {
                    try syncLiveFile(url, bound)
                    return
                }
                try? FileManager.default.removeItem(atPath: syncTarget.path + "-wal")
                try? FileManager.default.removeItem(atPath: syncTarget.path + "-shm")
                try? FileManager.default.removeItem(at: stashURL)
                try FileManager.default.moveItem(at: syncTarget, to: stashURL)
                try FileManager.default.copyItem(at: syncFixture, to: syncTarget)
                do {
                    try syncLiveFile(url, bound)
                } catch {
                    try? FileManager.default.removeItem(at: syncTarget)
                    try? FileManager.default.moveItem(at: stashURL, to: syncTarget)
                    throw error
                }
                // Live sync unexpectedly flushed the replacement: restore the
                // original and report the false-proof window explicitly.
                try? FileManager.default.removeItem(at: syncTarget)
                try? FileManager.default.moveItem(at: stashURL, to: syncTarget)
                XCTFail("Live sync must reject the replacement before flushing it")
                throw SQLiteArchiveDatabase.StoreError.exec("replacement-then-restore flushed the replacement before restore; refusing proof (expected device \(bound.device) inode \(bound.inode) binding)")
            },
            synchronizeDirectory: liveSeam.synchronizeDirectory
        )
        let restoreDatabase = try SQLiteArchiveDatabase(databaseURL: databaseURL, recoverySeam: restoreSeam)
        do {
            try restoreDatabase.proveRecoveryPersistence()
            XCTFail("replacement-then-restore during file sync must fail closed")
        } catch {
            let message = "\(error)"
            XCTAssertTrue(
                message.contains("refusing to sync unrelated replacement"),
                "must report replacement identity, got \(error)"
            )
        }
        // The original pathname was restored, and recovery evidence stays
        // readable at the retained location.
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path), "original pathname must be restored after the fault")
        let preservedDatabase = try SQLiteArchiveDatabase(databaseURL: preservedURL)
        let preservedStore = try SQLiteVaultTransferStore(database: preservedDatabase)
        XCTAssertEqual(try preservedStore.record(id: record.id), record, "failed proof must preserve recovery evidence")
    }

    func testCheckpointRejectsNonPositiveFrameCounts() throws {
        // Non-WAL/inapplicable checkpoint rows report `-1 == -1`: without a
        // non-negative guard that vacuous equality would pass as proof.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-vault-durability-checkpoint-frames-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("nonwal.sqlite")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            XCTFail("cannot open non-WAL fixture")
            return
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "PRAGMA journal_mode=DELETE;", nil, nil, nil) == SQLITE_OK else {
            XCTFail("cannot set DELETE journal mode")
            return
        }
        guard sqlite3_exec(db, "CREATE TABLE t(x TEXT);", nil, nil, nil) == SQLITE_OK else {
            XCTFail("cannot create fixture table")
            return
        }
        XCTAssertThrowsError(try SQLiteArchiveDatabase.checkpointTruncateStrict(db), "negative frame counts must fail closed") { error in
            XCTAssertTrue("\(error)".contains("checkpoint"), "must report checkpoint refusal, got \(error)")
        }
    }

    func testTransferRecordRoundTripUnderFullSyncConfiguration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-vault-durability-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteVaultTransferStore(databaseURL: root.appendingPathComponent("vault.sqlite"))
        let record = VaultTransferRecord(
            projectID: ProjectID(),
            sourceURL: root.appendingPathComponent("active/project"),
            stagingURL: root.appendingPathComponent("archive/.niko-staging/project"),
            destinationURL: root.appendingPathComponent("archive/generations/project"),
            state: .awaitingProviderDurability,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try store.save(record)
        XCTAssertEqual(try store.record(id: record.id), record)
    }

    private func pragmaString(_ database: SQLiteArchiveDatabase, _ sql: String) throws -> String {
        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW,
                  let cString = sqlite3_column_text(statement, 0) else {
                throw DurabilityPragmaError.unreadable(sql)
            }
            return String(cString: cString)
        }
    }

    private func pragmaInt(_ database: SQLiteArchiveDatabase, _ sql: String) throws -> Int64 {
        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else {
                throw DurabilityPragmaError.unreadable(sql)
            }
            return sqlite3_column_int64(statement, 0)
        }
    }

    /// Different valid SQLite fixture used for actual same-path replacement
    /// faults. Checkpointed (TRUNCATE) so the main file alone carries the
    /// marker; copying only the main file yields a readable replacement.
    private func makeReplacementSQLiteFixture(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw DurabilityPragmaError.unreadable("open replacement fixture \(url.path)")
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK else {
            throw DurabilityPragmaError.unreadable("replacement WAL \(url.path)")
        }
        let sanitized = marker.replacingOccurrences(of: "'", with: "")
        let sql = "CREATE TABLE IF NOT EXISTS replacement_probe(marker TEXT); DELETE FROM replacement_probe; INSERT INTO replacement_probe VALUES('\(sanitized)');"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DurabilityPragmaError.unreadable("replacement content \(url.path)")
        }
        var checkpoint: OpaquePointer?
        defer { sqlite3_finalize(checkpoint) }
        guard sqlite3_prepare_v2(db, "PRAGMA wal_checkpoint(TRUNCATE);", -1, &checkpoint, nil) == SQLITE_OK,
              sqlite3_step(checkpoint) == SQLITE_ROW else {
            throw DurabilityPragmaError.unreadable("replacement checkpoint \(url.path)")
        }
    }

    /// Actual same-path replacement: remove the target main file (plus stale
    /// `-wal`/`-shm`) while the original connection stays open to the old
    /// inode, then copy the fixture main file to the same pathname (new
    /// inode, identical `sqlite3_db_filename` string).
    private func replaceSQLiteFileAtPath(_ target: URL, withFixture fixture: URL) throws {
        try? FileManager.default.removeItem(atPath: target.path + "-wal")
        try? FileManager.default.removeItem(atPath: target.path + "-shm")
        try FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: fixture, to: target)
    }

    private func replacementMarker(on database: SQLiteArchiveDatabase) throws -> String {
        try database.withConnection { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "SELECT marker FROM replacement_probe LIMIT 1;", -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW,
                  let cString = sqlite3_column_text(statement, 0) else {
                throw DurabilityPragmaError.unreadable("replacement_probe")
            }
            return String(cString: cString)
        }
    }
}

// MARK: - Test seam helpers

private final class FlushLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var events: [String] { lock.withLock { stored } }

    func append(_ event: String) { lock.withLock { stored.append(event) } }
}

private final class CancellationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    func check() throws {
        let count = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        if count > limit { throw CancellationError() }
    }
}

// Foundation path spellings mix `/var/...` (fixture/temp root, even after
// `resolvingSymlinksInPath().standardized` on this Mac) and
// `/private/var/...` (directory-listing children). Never compare `url.path`
// directly for fault identity or log assertions: normalize the well-known
// `/private` prefix explicitly, so every intended fault actually fires.
private func normalizedDurabilityTestPath(_ url: URL) -> String {
    let path = url.standardizedFileURL.path
    if path.hasPrefix("/private/var/") { return String(path.dropFirst("/private".count)) }
    if path == "/private/var" { return "/var" }
    if path.hasPrefix("/private/tmp/") { return String(path.dropFirst("/private".count)) }
    if path == "/private/tmp" { return "/tmp" }
    return path
}

private func durabilityTestURLsMatch(_ a: URL, _ b: URL) -> Bool {
    normalizedDurabilityTestPath(a) == normalizedDurabilityTestPath(b)
}

private func normalizedDurabilityEvent(_ event: String) -> String {
    event
        .replacingOccurrences(of: "/private/var/", with: "/var/")
        .replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
}

private func normalizedDurabilityEvents(_ events: [String]) -> [String] {
    events.map(normalizedDurabilityEvent)
}

private func durabilitySyncEvent(kind: String, url: URL) -> String {
    "\(kind) \(normalizedDurabilityTestPath(url))"
}

private func recordingSeam(log: FlushLog) -> LocalVaultFlushSeam {
    let live = LocalVaultFlushSeam.live
    return LocalVaultFlushSeam(
        deviceIDOf: live.deviceIDOf,
        inodeOf: live.inodeOf,
        filesystemTypeOf: live.filesystemTypeOf,
        filesystemTypeOfDescriptor: live.filesystemTypeOfDescriptor,
        synchronize: { _, url, isDirectory in
            log.append("sync \(isDirectory ? "dir" : "file") \(url.path)")
        },
        drainDeviceQueue: { _, url, isDirectory in
            log.append("drain \(isDirectory ? "dir" : "file") \(url.path)")
        },
        checkCancellation: live.checkCancellation
    )
}

private enum DurabilityPragmaError: Error {
    case unreadable(String)
}
