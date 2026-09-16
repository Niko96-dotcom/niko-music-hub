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
}
