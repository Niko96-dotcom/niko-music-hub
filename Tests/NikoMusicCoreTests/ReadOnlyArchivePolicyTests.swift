import XCTest
@testable import NikoMusicCore

final class ReadOnlyArchivePolicyTests: XCTestCase {
    func testWriteProbeDeniedUnderFixtureRoot() throws {
        try CubaseFixtures.ensureGenerated()
        let policy = ReadOnlyArchivePolicy()
        XCTAssertTrue(policy.writeProbeDenied(under: CubaseFixtures.archiveRoot))
    }

    func testAllowsWriteOutsideArchiveRoot() {
        let policy = ReadOnlyArchivePolicy()
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("archive", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-write.txt")
        XCTAssertTrue(policy.allowsWrite(at: outside, archiveRoot: archive))
    }

    func testEnforceNoWriteThrowsForPathsInsideRoot() {
        let policy = ReadOnlyArchivePolicy()
        let archive = URL(fileURLWithPath: "/tmp/archive", isDirectory: true)
        let inside = archive.appendingPathComponent("probe.txt")
        XCTAssertThrowsError(try policy.enforceNoWrite(at: inside, archiveRoot: archive)) { error in
            XCTAssertEqual(error as? ReadOnlyArchivePolicyError, .writeDenied(inside))
        }
    }

    func testEnforceNoWriteDeniesSymlinkIntoArchiveRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("readonly-symlink-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        let link = outside.appendingPathComponent("drafts", isDirectory: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createSymbolicLink(at: link, withDestinationURL: archive)

        let policy = ReadOnlyArchivePolicy(fileManager: fm)
        XCTAssertFalse(policy.allowsWrite(at: link, archiveRoot: archive))
        XCTAssertThrowsError(try policy.enforceNoWrite(at: link, archiveRoots: [archive])) { error in
            XCTAssertEqual(error as? ReadOnlyArchivePolicyError, .writeDenied(link))
        }
    }
}
