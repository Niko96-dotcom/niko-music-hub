import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import NikoMusicCore

final class VaultManifestTests: XCTestCase {
    func testManifestBuildAndVerificationIgnoreOnlyExactDSStoreMetadataFiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Audio", isDirectory: true)
        let more = nested.appendingPathComponent("More", isDirectory: true)
        try FileManager.default.createDirectory(at: more, withIntermediateDirectories: true)
        try Data("project".utf8).write(to: root.appendingPathComponent("Song.cpr"))
        try Data("root metadata".utf8).write(to: root.appendingPathComponent(".DS_Store"))
        try Data("nested metadata".utf8).write(to: nested.appendingPathComponent(".DS_Store"))
        try Data("substantive exact-prefix".utf8).write(
            to: root.appendingPathComponent(".DS_Store.keep")
        )
        try Data("substantive exact-suffix".utf8).write(
            to: nested.appendingPathComponent("take.DS_Store")
        )
        let builder = VaultManifestBuilder()

        let manifest = try builder.build(at: root)
        let paths = Set(manifest.entries.map(\.relativePath))

        XCTAssertFalse(paths.contains(".DS_Store"))
        XCTAssertFalse(paths.contains("Audio/.DS_Store"))
        XCTAssertTrue(paths.contains(".DS_Store.keep"))
        XCTAssertTrue(paths.contains("Audio/take.DS_Store"))

        try Data("changed root metadata".utf8).write(to: root.appendingPathComponent(".DS_Store"))
        try FileManager.default.removeItem(at: nested.appendingPathComponent(".DS_Store"))
        try Data("new nested metadata".utf8).write(
            to: more.appendingPathComponent(".DS_Store"),
            options: .atomic
        )
        try builder.verify(manifest, at: root)

        try Data("mutated substantive file".utf8).write(
            to: root.appendingPathComponent(".DS_Store.keep"),
            options: .atomic
        )
        XCTAssertThrowsError(try builder.verify(manifest, at: root)) {
            XCTAssertEqual($0 as? VaultManifestError, .mismatch)
        }
    }

    func testSHA256ManifestDetectsSameSizeContentMutation() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("Audio/take.wav")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("AAAA".utf8).write(to: file)
        let builder = VaultManifestBuilder()
        let manifest = try builder.build(at: root)

        try Data("BBBB".utf8).write(to: file)

        XCTAssertThrowsError(try builder.verify(manifest, at: root)) {
            XCTAssertEqual($0 as? VaultManifestError, .mismatch)
        }
    }

    func testManifestRefusesSymbolicLinks() throws {
        let root = temporaryRoot()
        let outside = temporaryRoot().appendingPathExtension("txt")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape.wav"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try VaultManifestBuilder().build(at: root)) {
            XCTAssertEqual($0 as? VaultManifestError, .unsupportedSymbolicLink("escape.wav"))
        }
    }

    func testManifestHashesLargeFilesInMultipleChunksWithoutChangingDigest() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data((0..<(2_500_000)).map { UInt8($0 % 251) })
        try data.write(to: root.appendingPathComponent("large-audio.wav"))

        let manifest = try VaultManifestBuilder().build(at: root)
        let entry = try XCTUnwrap(manifest.entries.first { $0.relativePath == "large-audio.wav" })

        XCTAssertEqual(entry.byteCount, Int64(data.count))
        XCTAssertEqual(entry.sha256, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    func testManifestFailsClosedWhenDirectoryEnumerationFails() throws {
        let root = temporaryRoot()
        let blocked = root.appendingPathComponent("blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data("hidden".utf8).write(to: blocked.appendingPathComponent("hidden.cpr"))
        defer {
            chmod(blocked.path, S_IRWXU)
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertEqual(chmod(blocked.path, 0), 0)

        XCTAssertThrowsError(try VaultManifestBuilder().build(at: root)) { error in
            guard case VaultManifestError.enumerationFailed = error else {
                return XCTFail("expected enumeration failure, got \(error)")
            }
        }
    }

    func testVerifyRejectsUnexpectedEntryBeforeOpeningAnyFileContent() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("expected".utf8).write(to: root.appendingPathComponent("Expected.cpr"))
        let manifest = try VaultManifestBuilder().build(at: root)
        try Data("online-placeholder".utf8).write(to: root.appendingPathComponent("Unexpected.wav"))
        let hashSpy = VaultManifestHashSpy()
        let verifier = VaultManifestBuilder(contentHasher: hashSpy.hash)

        XCTAssertThrowsError(try verifier.verify(manifest, at: root)) {
            XCTAssertEqual($0 as? VaultManifestError, .mismatch)
        }
        XCTAssertTrue(hashSpy.openedURLs.isEmpty)
    }

    func testVerifyRejectsRegularFileSwappedForSymlinkDuringHashing() throws {
        let root = temporaryRoot()
        let outside = temporaryRoot().appendingPathExtension("wav")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("a.wav")
        let swapped = root.appendingPathComponent("b.wav")
        try Data("first take".utf8).write(to: first)
        try Data("second take".utf8).write(to: swapped)
        try Data("second take".utf8).write(to: outside)
        let manifest = try VaultManifestBuilder().build(at: root)
        let verifier = VaultManifestBuilder(contentHasher: { url in
            if url.lastPathComponent == "a.wav",
               (try? swapped.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true {
                try FileManager.default.removeItem(at: swapped)
                try FileManager.default.createSymbolicLink(at: swapped, withDestinationURL: outside)
            }
            return try VaultManifestBuilder.hashRegularFile(at: url)
        })

        XCTAssertThrowsError(try verifier.verify(manifest, at: root)) { error in
            guard case VaultManifestError.unsupportedSymbolicLink = error else {
                return XCTFail("expected the swapped link to be refused, got \(error)")
            }
        }
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: swapped.path),
            outside.path,
            "the swap must have happened between inventory and hash"
        )
    }

    func testVerifyRejectsFIFOSwappedInDuringHashingWithoutBlocking() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let swapped = root.appendingPathComponent("b.wav")
        try Data("first take".utf8).write(to: root.appendingPathComponent("a.wav"))
        try Data("second take".utf8).write(to: swapped)
        let manifest = try VaultManifestBuilder().build(at: root)
        let verifier = VaultManifestBuilder(contentHasher: { url in
            if url.lastPathComponent == "a.wav" {
                try FileManager.default.removeItem(at: swapped)
                XCTAssertEqual(mkfifo(swapped.path, 0o600), 0)
            }
            return try VaultManifestBuilder.hashRegularFile(at: url)
        })

        XCTAssertThrowsError(try verifier.verify(manifest, at: root)) { error in
            guard case VaultManifestError.unsupportedFileType = error else {
                return XCTFail("expected the FIFO to be refused, got \(error)")
            }
        }
    }

    func testBuildAndVerifyThrowCancellationBetweenFilesAndChunks() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["a.wav", "b.wav", "c.wav"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        let manifest = try VaultManifestBuilder().build(at: root)

        // A Task cancelled before it starts hashes nothing.
        for operation in ["build", "verify"] {
            let hasher = CancelOnHashHook(below: root)
            let builder = VaultManifestBuilder(contentHasher: hasher.hash)
            let outcome = await Task {
                withUnsafeCurrentTask { $0?.cancel() }
                if operation == "build" {
                    _ = try builder.build(at: root)
                } else {
                    try builder.verify(manifest, at: root)
                }
            }.result
            XCTAssertThrowsError(try outcome.get(), operation) { XCTAssertTrue($0 is CancellationError, "\(operation): \($0)") }
            XCTAssertEqual(hasher.hashedCount, 0, "\(operation) must not hash after cancel")
        }

        // Cancelling while file 1 is hashed stops before file 2.
        for operation in ["build", "verify", "verifyArchive"] {
            let hasher = CancelOnHashHook(below: root)
            hasher.arm()
            let builder = VaultManifestBuilder(contentHasher: hasher.hash)
            let outcome = await Task {
                switch operation {
                case "build": _ = try builder.build(at: root)
                case "verify": try builder.verify(manifest, at: root)
                default: try builder.verifyArchive(manifest, at: root)
                }
            }.result
            XCTAssertThrowsError(try outcome.get(), operation) { XCTAssertTrue($0 is CancellationError, "\(operation): \($0)") }
            XCTAssertEqual(hasher.hashedCount, 1, "\(operation) must stop before the next file")
        }

        // The read loop itself checks cancellation, so one multi-GB file
        // cannot hold a cancelled transfer until its last chunk.
        let large = root.appendingPathComponent("large.wav")
        try Data(repeating: 0x5a, count: 3 * 1_048_576).write(to: large)
        let chunkLog = HashedChunkLog()
        let hashOutcome = await Task {
            try VaultManifestBuilder.hashRegularFile(at: large, afterChunk: { hashed in
                chunkLog.append(hashed)
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }.result
        XCTAssertThrowsError(try hashOutcome.get()) { XCTAssertTrue($0 is CancellationError, "\($0)") }
        XCTAssertEqual(chunkLog.values, [1_048_576], "no chunk may be read after the one that saw the cancel")
        let uncancelled = try VaultManifestBuilder.hashRegularFile(at: large)
        XCTAssertEqual(uncancelled.byteCount, 3 * 1_048_576)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vault-manifest-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class VaultManifestHashSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var storedOpenedURLs: [URL] = []

    var openedURLs: [URL] { lock.withLock { storedOpenedURLs } }

    func hash(_ url: URL) throws -> (byteCount: Int64, sha256: String) {
        lock.withLock { storedOpenedURLs.append(url) }
        return (0, "unexpected")
    }
}

private final class HashedChunkLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Int64] = []

    var values: [Int64] { lock.withLock { stored } }
    func append(_ value: Int64) { lock.withLock { stored.append(value) } }
}
