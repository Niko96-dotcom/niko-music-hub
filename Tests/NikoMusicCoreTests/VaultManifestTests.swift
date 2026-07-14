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

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vault-manifest-\(UUID().uuidString)", isDirectory: true)
    }
}
