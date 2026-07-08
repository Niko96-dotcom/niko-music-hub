import XCTest
@testable import NikoMusicCore

final class NewSongFolderCreatorTests: XCTestCase {
    func testCreateRejectsSymlinkedOutputInsideArchiveRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("new-song-symlink-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        let linkedDraftRoot = outside.appendingPathComponent("New Song Drafts", isDirectory: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createSymbolicLink(at: linkedDraftRoot, withDestinationURL: archive)

        XCTAssertThrowsError(
            try NewSongFolderCreator.create(
                request: NewSongRequest(name: "Should Not Land In Archive", root: linkedDraftRoot),
                fileManager: fm,
                protectedRoots: [archive]
            )
        ) { error in
            XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .archiveRootIsReadOnly)
        }

        XCTAssertFalse(
            fm.fileExists(atPath: archive.appendingPathComponent("Should Not Land In Archive", isDirectory: true).path)
        )
    }

    func testCreateAllowsOutputOutsideArchiveRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("new-song-ok-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let drafts = base.appendingPathComponent("drafts", isDirectory: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try fm.createDirectory(at: drafts, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let song = try NewSongFolderCreator.create(
            request: NewSongRequest(name: "Legit Draft", root: drafts),
            fileManager: fm,
            protectedRoots: [archive]
        )
        XCTAssertTrue(fm.fileExists(atPath: song.folderPath.path))
        XCTAssertTrue(song.folderPath.path.hasPrefix(drafts.standardizedFileURL.path))
    }
}
