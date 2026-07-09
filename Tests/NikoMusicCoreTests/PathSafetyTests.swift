import XCTest
@testable import NikoMusicCore

final class PathSafetyTests: XCTestCase {
    func testRejectsPathOutsideAllowedRoots() throws {
        let safety = PathSafety()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("niko-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("niko-outside.txt")
        try "x".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        XCTAssertThrowsError(try safety.resolve(outside, allowedRoots: [root])) { error in
            XCTAssertEqual(error as? PathSafetyError, .pathOutsideAllowedRoots(outside.standardizedFileURL))
        }
    }

    func testAcceptsPathInsideRoot() throws {
        let safety = PathSafety()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("niko-inner-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let inside = root.appendingPathComponent("song/file.wav")
        try FileManager.default.createDirectory(at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: inside, atomically: true, encoding: .utf8)

        let resolved = try safety.resolve(inside, allowedRoots: [root])
        XCTAssertTrue(resolved.path.hasPrefix(root.standardizedFileURL.path))
    }

    func testResolveAcceptsPathInsideSymlinkedArchiveRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("path-safety-resolve-root-link-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let link = base.appendingPathComponent("archive-link", isDirectory: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        try fm.createSymbolicLink(at: link, withDestinationURL: archive)

        let inside = archive.appendingPathComponent("song/file.wav")
        try fm.createDirectory(at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: inside, atomically: true, encoding: .utf8)

        let safety = PathSafety(fileManager: fm)
        let resolved = try safety.resolve(inside, allowedRoots: [link])
        XCTAssertEqual(
            resolved.standardizedFileURL.resolvingSymlinksInPath().path,
            inside.standardizedFileURL.resolvingSymlinksInPath().path
        )
    }

    func testResolveRejectsPathEscapingAllowedRoots() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("path-safety-resolve-escape-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let link = base.appendingPathComponent("archive-link", isDirectory: true)
        let outside = base.appendingPathComponent("outside.txt")
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        try fm.createSymbolicLink(at: link, withDestinationURL: archive)
        try "outside".write(to: outside, atomically: true, encoding: .utf8)

        let safety = PathSafety(fileManager: fm)
        XCTAssertThrowsError(try safety.resolve(outside, allowedRoots: [link])) { error in
            XCTAssertEqual(
                error as? PathSafetyError,
                .pathOutsideAllowedRoots(outside.standardizedFileURL.resolvingSymlinksInPath())
            )
        }
    }

    func testResolvedContainedDetectsSymlinkIntoRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("path-safety-symlink-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        let link = outside.appendingPathComponent("into-archive", isDirectory: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        try fm.createSymbolicLink(at: link, withDestinationURL: archive)

        let safety = PathSafety(fileManager: fm)
        XCTAssertTrue(safety.isResolvedContained(link, in: [archive]))
        XCTAssertFalse(safety.isResolvedContained(outside, in: [archive]))
    }
}
