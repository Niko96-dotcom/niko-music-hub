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
}
