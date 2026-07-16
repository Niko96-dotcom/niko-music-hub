import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import NikoMusicCore

final class VaultManifestTests: XCTestCase {
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

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vault-manifest-\(UUID().uuidString)", isDirectory: true)
    }
}
