import Foundation
import XCTest

final class ProjectVaultFixtureTests: XCTestCase {
    func testSyntheticCubaseFixtureContainsAllRequiredVariantsWithoutRealProjectData() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let fixture = try ProjectVaultSyntheticFixtures.make(in: parent)
        let fm = FileManager.default

        XCTAssertTrue(fm.fileExists(atPath: fixture.project.appendingPathComponent("Synthetic Song.cpr").path))
        XCTAssertTrue(fm.fileExists(atPath: fixture.project.appendingPathComponent("Pool.xml").path))
        XCTAssertTrue(fm.fileExists(atPath: fixture.existingMedia.path))
        XCTAssertFalse(fm.fileExists(atPath: fixture.missingMedia.path))
        XCTAssertTrue(fm.fileExists(atPath: fixture.alias.path))
        XCTAssertEqual(fixture.symlink.resolvingSymlinksInPath(), fixture.existingMedia.deletingLastPathComponent())
        XCTAssertTrue(fm.fileExists(atPath: fixture.conflictCopy.path))

        let attributes = try fm.attributesOfItem(atPath: fixture.sparseFile.path)
        XCTAssertEqual((attributes[.size] as? NSNumber)?.int64Value, 2_000_000_000)
        let values = try fixture.sparseFile.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        XCTAssertLessThan(values.totalFileAllocatedSize ?? .max, 10_000_000)
    }
}
