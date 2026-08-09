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

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("niko-music-hub-sidecar-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
