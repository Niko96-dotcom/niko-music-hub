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
}
