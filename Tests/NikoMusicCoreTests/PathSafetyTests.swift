import Darwin
import XCTest
@testable import NikoMusicCore

final class PathSafetyTests: XCTestCase {
    func testRejectsPathOutsideAllowedRoots() throws {
        let safety = PathSafety()
        let parent = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("niko-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)

        let outside = parent.appendingPathComponent("niko-outside.txt")
        try "x".write(to: outside, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try safety.resolve(outside, allowedRoots: [root])) { error in
            XCTAssertEqual(error as? PathSafetyError, .pathOutsideAllowedRoots(outside.standardizedFileURL))
        }
    }

    func testAcceptsPathInsideRoot() throws {
        let safety = PathSafety()
        let parent = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("niko-inner-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)

        let inside = root.appendingPathComponent("song/file.wav")
        try FileManager.default.createDirectory(at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: inside, atomically: true, encoding: .utf8)

        let resolved = try safety.resolve(inside, allowedRoots: [root])
        XCTAssertTrue(resolved.path.hasPrefix(root.standardizedFileURL.path))
    }

    func testFixtureAllocationsAreIndependentAndPreserveSiblingCanaries() throws {
        let fm = FileManager.default
        let parent = try makeFixtureDirectory()
        defer { try? fm.removeItem(at: parent) }

        let canaryFile = parent.appendingPathComponent("niko-outside.txt")
        try "original outside".write(to: canaryFile, atomically: true, encoding: .utf8)
        let canaryRoots = ["niko-root", "niko-inner-root"].map {
            parent.appendingPathComponent($0, isDirectory: true)
        }
        for root in canaryRoots {
            try fm.createDirectory(at: root, withIntermediateDirectories: false)
            try "original root".write(to: root.appendingPathComponent("retained.txt"), atomically: true, encoding: .utf8)
        }

        do {
            let first = try makeFixtureDirectory(in: parent)
            defer { try? fm.removeItem(at: first) }
            let second = try makeFixtureDirectory(in: parent)
            defer { try? fm.removeItem(at: second) }
            XCTAssertNotEqual(first, second)
            XCTAssertEqual(first.deletingLastPathComponent().path, parent.path)
            XCTAssertEqual(second.deletingLastPathComponent().path, parent.path)

            let firstFile = first.appendingPathComponent("niko-outside.txt")
            let secondFile = second.appendingPathComponent("niko-outside.txt")
            try "first".write(to: firstFile, atomically: true, encoding: .utf8)
            try "second".write(to: secondFile, atomically: true, encoding: .utf8)
            XCTAssertEqual(try String(contentsOf: firstFile, encoding: .utf8), "first")
            XCTAssertEqual(try String(contentsOf: secondFile, encoding: .utf8), "second")
        }

        XCTAssertEqual(try String(contentsOf: canaryFile, encoding: .utf8), "original outside")
        for root in canaryRoots {
            XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path), ["retained.txt"])
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("retained.txt"), encoding: .utf8), "original root")
        }
        XCTAssertEqual(
            Set(try fm.contentsOfDirectory(atPath: parent.path)),
            ["niko-root", "niko-inner-root", "niko-outside.txt"]
        )
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

    func testResolvedContainedHandlesMissingChildUnderTmpSymlink() throws {
        let fm = FileManager.default
        let visibleRoot = URL(
            fileURLWithPath: "/tmp/path-safety-missing-child-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: visibleRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: visibleRoot) }

        let missingChild = visibleRoot.appendingPathComponent("not-created-yet.wav")
        XCTAssertFalse(fm.fileExists(atPath: missingChild.path))

        let safety = PathSafety(fileManager: fm)
        XCTAssertTrue(safety.isResolvedContained(missingChild, in: [visibleRoot]))
    }

    func testResolvedContainedHandlesMissingChildThroughDirectorySymlink() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(
            "path-safety-missing-child-link-\(UUID().uuidString)",
            isDirectory: true
        )
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        let link = outside.appendingPathComponent("into-archive", isDirectory: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createSymbolicLink(at: link, withDestinationURL: archive)

        let missingChild = link.appendingPathComponent("not-created-yet.wav")
        let safety = PathSafety(fileManager: fm)
        XCTAssertTrue(safety.isResolvedContained(missingChild, in: [archive]))
    }

    func testFilesystemRootContainsEveryPath() throws {
        let fm = FileManager.default
        let parent = try makeFixtureDirectory()
        defer { try? fm.removeItem(at: parent) }
        let inside = parent.appendingPathComponent("not-created-yet.wav")
        let fsRoot = URL(fileURLWithPath: "/", isDirectory: true)

        let safety = PathSafety(fileManager: fm)
        XCTAssertTrue(safety.isContained(inside, in: [fsRoot]))
        XCTAssertTrue(safety.isResolvedContained(inside, in: [fsRoot]))
        XCTAssertTrue(safety.resolvedPathsOverlapIgnoringCase(inside, fsRoot))
        XCTAssertTrue(safety.resolvedPathsOverlapIgnoringCase(fsRoot, inside))
    }

    private func makeFixtureDirectory(
        in parent: URL = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
    ) throws -> URL {
        var template = Array(parent.appendingPathComponent("nmh-path-safety-XXXXXX").path.utf8CString)
        return try template.withUnsafeMutableBufferPointer { buffer in
            guard let path = mkdtemp(buffer.baseAddress) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
    }
}
