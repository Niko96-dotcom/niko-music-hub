import XCTest
@testable import NikoMusicCore

final class SidecarNotesReaderTests: XCTestCase {
    func testRejectsSymbolicLinkToExternalNotes() throws {
        let root = try makeTemporaryRoot()
        let externalRoot = try makeTemporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: externalRoot)
        }

        let externalNotes = externalRoot.appendingPathComponent("private.txt")
        try Data("must not escape the archive".utf8).write(to: externalNotes)
        let notes = root.appendingPathComponent(SidecarNotesReader.fileName)
        try FileManager.default.createSymbolicLink(at: notes, withDestinationURL: externalNotes)

        XCTAssertNil(SidecarNotesReader().readNotes(in: root))
    }

    func testCapsLargeNotesAndMarksTheResultAsTruncated() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = String(repeating: "a", count: SidecarNotesReader.maximumByteCount + 1)
        try Data(source.utf8).write(to: root.appendingPathComponent(SidecarNotesReader.fileName))

        let notes = try XCTUnwrap(SidecarNotesReader().readNotes(in: root))
        XCTAssertTrue(notes.hasSuffix("(notes.txt truncated at 64 KiB)"))
        XCTAssertLessThanOrEqual(
            notes.utf8.count,
            SidecarNotesReader.maximumByteCount + SidecarNotesReader.truncationMarker.utf8.count
        )
    }

    func testReadsAndTrimsOrdinaryNotes() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("\n useful note \n".utf8).write(to: root.appendingPathComponent(SidecarNotesReader.fileName))

        XCTAssertEqual(SidecarNotesReader().readNotes(in: root), "useful note")
    }

    func testRejectsNotesThatAreNotARegularFileInsideTheFolder() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let notes = root.appendingPathComponent(SidecarNotesReader.fileName)

        // A link that stays inside the folder is still a link.
        try Data("inside".utf8).write(to: root.appendingPathComponent("real.txt"))
        try fm.createSymbolicLink(atPath: notes.path, withDestinationPath: "real.txt")
        XCTAssertNil(SidecarNotesReader().readNotes(in: root))

        try fm.removeItem(at: notes)
        try fm.createSymbolicLink(atPath: notes.path, withDestinationPath: SidecarNotesReader.fileName)
        XCTAssertNil(SidecarNotesReader().readNotes(in: root), "link loop")

        try fm.removeItem(at: notes)
        try fm.createDirectory(at: notes, withIntermediateDirectories: false)
        XCTAssertNil(SidecarNotesReader().readNotes(in: root), "directory")

        try fm.removeItem(at: notes)
        XCTAssertEqual(mkfifo(notes.path, 0o600), 0)
        XCTAssertNil(SidecarNotesReader().readNotes(in: root), "FIFO")
    }

    func testMissingOrNonDirectoryFolderHasNoNotes() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(SidecarNotesReader().readNotes(in: root.appendingPathComponent("missing")))
        XCTAssertNil(SidecarNotesReader().readNotes(in: root), "no notes.txt")

        let file = root.appendingPathComponent("song.cpr")
        try Data("x".utf8).write(to: file)
        XCTAssertNil(SidecarNotesReader().readNotes(in: file))
    }

    /// The folder itself must not be reached through a link: only the real folder yields notes.
    func testRefusesNotesWhenFolderItselfIsALink() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("Real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        try Data("linked note".utf8).write(to: real.appendingPathComponent(SidecarNotesReader.fileName))
        let alias = root.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)

        XCTAssertNil(SidecarNotesReader().readNotes(in: alias))
        XCTAssertEqual(SidecarNotesReader().readNotes(in: URL(fileURLWithPath: "/private" + real.path)), "linked note")
    }

    /// A song folder that is a link to an outside folder must never surface the outside notes.
    func testLinkedFolderNeverReturnsOutsideNotesMarker() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let marker = "OUTSIDE-MARKER-\(UUID().uuidString)"
        try Data(marker.utf8).write(to: outside.appendingPathComponent(SidecarNotesReader.fileName))
        let alias = root.appendingPathComponent("Song")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)

        XCTAssertNil(SidecarNotesReader().readNotes(in: alias))
        // Sanity: the marker is really there when read through the real folder.
        XCTAssertEqual(SidecarNotesReader().readNotes(in: outside), marker)
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("niko-music-hub-sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
