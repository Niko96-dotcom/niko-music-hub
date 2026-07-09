import XCTest
@testable import NikoMusicCore

final class OutputWriteGuardTests: XCTestCase {
    func testRejectsDirectOutputPathInsideArchiveRoot() {
        let guardrail = OutputWriteGuard()
        let archive = URL(fileURLWithPath: "/tmp/archive", isDirectory: true)
        let inside = archive.appendingPathComponent("Inbox", isDirectory: true)

        XCTAssertThrowsError(try guardrail.validateCanWriteOutput(to: inside, archiveRoots: [archive])) { error in
            XCTAssertEqual(error as? OutputWriteGuardError, .outputInsideArchiveRoot(inside))
        }
    }

    func testAllowsOutputPathOutsideArchiveRoot() throws {
        let guardrail = OutputWriteGuard()
        let archive = URL(fileURLWithPath: "/tmp/archive", isDirectory: true)
        let outside = URL(fileURLWithPath: "/tmp/outside-inbox", isDirectory: true)

        XCTAssertNoThrow(try guardrail.validateCanWriteOutput(to: outside, archiveRoots: [archive]))
    }

    func testRejectsSymlinkedOutputFolderInsideArchiveRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("output-guard-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        let link = outside.appendingPathComponent("inbox-link", isDirectory: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createSymbolicLink(at: link, withDestinationURL: archive)

        let guardrail = OutputWriteGuard(fileManager: fm)

        XCTAssertThrowsError(try guardrail.validateCanWriteOutput(to: link, archiveRoots: [archive])) { error in
            XCTAssertEqual(error as? OutputWriteGuardError, .outputInsideArchiveRoot(link))
        }
    }
}
