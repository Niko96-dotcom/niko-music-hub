import XCTest
@testable import NikoMusicCore

final class ScanExclusionPolicyTests: XCTestCase {
    func testSkipsBackupFolderDuringScan() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubExclude-\(UUID().uuidString)", isDirectory: true)
        let included = root.appendingPathComponent("Included Song", isDirectory: true)
        let backup = root.appendingPathComponent("backup", isDirectory: true)
        try FileManager.default.createDirectory(at: included, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: included.appendingPathComponent("Included Song.cpr").path,
            contents: Data("fixture".utf8)
        )
        FileManager.default.createFile(
            atPath: backup.appendingPathComponent("Hidden Song.cpr").path,
            contents: Data("fixture".utf8)
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = CubaseArchiveScanner(exclusionTerms: ["backup"])
        let result = try scanner.scan(roots: [root])

        XCTAssertEqual(result.songs.map(\.displayTitle), ["Included Song"])
        XCTAssertTrue(result.skippedEntries.contains { $0.label == "backup" })
    }
}
