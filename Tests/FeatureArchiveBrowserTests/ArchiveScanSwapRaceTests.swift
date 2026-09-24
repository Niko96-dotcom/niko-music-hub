import Foundation
@testable import NikoMusicCore
import XCTest

/// A folder inside a song replaced by a symbolic link to outside the archive while the scan is
/// running. Every archive is built under a fresh temporary directory; no real music is read.
final class ArchiveScanSwapRaceTests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var song: URL!
    private var outside: URL!

    /// Duration of the WAV header planted outside the archive; nothing inside is this long.
    private static let outsideSeconds = 7.0

    override func setUpWithError() throws {
        let fm = FileManager.default
        base = fm.temporaryDirectory.appendingPathComponent("nmh-swap-race-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("Archive", isDirectory: true)
        song = root.appendingPathComponent("Song", isDirectory: true)
        outside = base.appendingPathComponent("Outside", isDirectory: true)
        try fm.createDirectory(at: song.appendingPathComponent("Mixdown"), withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("placeholder".utf8).write(to: song.appendingPathComponent("Song v1.cpr"))
        try Self.wav(seconds: 1).write(to: song.appendingPathComponent("Mixdown/Song mix.wav"))
        try Self.wav(seconds: 1).write(to: song.appendingPathComponent("Song bounce.wav"))
        // Same name as the file inside, so a path-string check cannot tell them apart.
        try Self.wav(seconds: Self.outsideSeconds).write(to: outside.appendingPathComponent("Song mix.wav"))
        try Self.wav(seconds: Self.outsideSeconds).write(to: outside.appendingPathComponent("Stolen take.wav"))
        try Data("placeholder".utf8).write(to: outside.appendingPathComponent("Stolen v9.cpr"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    /// `Mixdown` is listed as a real folder, then swapped for a link before its children are
    /// listed and resolved. The enumerator follows the link and lists the outside files as
    /// `Song/Mixdown/...`, reporting none of them as a link.
    func testFolderSwappedForALinkAfterItWasListedIsNotScanned() throws {
        var scanner = MusicArchiveScanner()
        var swapped = false
        scanner.raceHooks.entryListed = { [self] url in
            guard !swapped, url.lastPathComponent == "Mixdown" else { return }
            swapped = true
            swapMixdownForLink()
        }
        let result = try scanner.scan(roots: [root])
        XCTAssertTrue(swapped)
        try assertNothingReadFromOutside(result)
    }

    /// The walk accepted `Mixdown/Song mix.wav` while it was inside; the folder is swapped before
    /// the file is opened for its duration.
    func testFolderSwappedForALinkBeforeThePreviewIsOpenedIsNotRead() throws {
        var scanner = MusicArchiveScanner()
        var swapped = false
        scanner.raceHooks.songWalked = { [self] folder in
            guard folder.lastPathComponent == "Song" else { return }
            swapped = true
            swapMixdownForLink()
        }
        let result = try scanner.scan(roots: [root])
        XCTAssertTrue(swapped)
        try assertNothingReadFromOutside(result)
        // Files the swap did not touch are still scanned.
        let songResult = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Song" })
        XCTAssertEqual(songResult.previewCandidates.map(\.fileName), ["Song bounce.wav"])
    }

    /// Without a race the same archive scans normally.
    func testUnswappedArchiveScansEveryFile() throws {
        let result = try MusicArchiveScanner().scan(roots: [root])
        let songResult = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Song" })
        XCTAssertEqual(Set(songResult.previewCandidates.map(\.fileName)), ["Song mix.wav", "Song bounce.wav"])
        XCTAssertEqual(songResult.previewCandidates.compactMap(\.durationSeconds), [1, 1])
    }

    /// The song folder itself is listed as a real directory at the archive root, then swapped
    /// for a link to outside before its walk finishes. Uses only the pre-existing `entryListed`
    /// hook, so it compiles on the original HEAD and fails there (the walk follows the swapped
    /// link through re-opened paths); the fix rejects the swapped base via its `O_NOFOLLOW`
    /// open and `dev`/`ino` verification and discards the song instead of returning outside
    /// (or dangling) paths.
    func testSongFolderSwappedForOutsideLinkBetweenEnumerationAndWalkIsNotScanned() throws {
        let innerSong = song.resolvingSymlinksInPath().path + "/"
        var scanner = MusicArchiveScanner()
        var swapped = false
        scanner.raceHooks.entryListed = { [self] _ in
            guard !swapped else { return }
            swapped = true
            swapSongForLink()
        }
        let result = try scanner.scan(roots: [root])
        XCTAssertTrue(swapped)
        guard let songResult = result.songs.first(where: { $0.originalFolderName == "Song" }) else {
            return
        }
        for preview in songResult.previewCandidates {
            XCTAssertNotEqual(
                preview.durationSeconds, Self.outsideSeconds,
                "read \(preview.filePath.path) outside the archive"
            )
            XCTAssertTrue(
                preview.filePath.resolvingSymlinksInPath().path.hasPrefix(innerSong),
                preview.filePath.path
            )
        }
        for version in songResult.projectVersions {
            XCTAssertTrue(
                version.filePath.resolvingSymlinksInPath().path.hasPrefix(innerSong),
                version.filePath.path
            )
        }
        XCTAssertFalse(songResult.previewCandidates.contains { $0.fileName == "Stolen take.wav" })
        XCTAssertFalse(songResult.projectVersions.contains { $0.fileName == "Stolen v9.cpr" })
    }

    /// The song folder is moved aside mid-walk and a DIFFERENT real directory (initially
    /// outside the root) is moved into its path. After the move the replacement is physically
    /// under the root, but its inode was not the one the walk enumerated and must be rejected.
    /// Uses only the pre-existing `entryListed` hook, so it compiles on the original HEAD and
    /// fails there (per-file opens re-resolve the swapped path and return the replacement's
    /// duration/notes); the fix pins the verified fd for the whole song and discards on the
    /// `dev`/`ino` mismatch before returning anything.
    func testSongFolderSwappedForDifferentRealDirectoryIsDiscarded() throws {
        let fm = FileManager.default
        try Data("inside note".utf8).write(to: song.appendingPathComponent("notes.txt"))
        let insideCPRDate = Date(timeIntervalSince1970: 1_700_000_000)
        try fm.setAttributes(
            [.modificationDate: insideCPRDate],
            ofItemAtPath: song.appendingPathComponent("Song v1.cpr").path
        )
        let replacement = base.appendingPathComponent("Replacement", isDirectory: true)
        try fm.createDirectory(at: replacement.appendingPathComponent("Mixdown"), withIntermediateDirectories: true)
        let outsideMarker = "OUTSIDE-REPLACEMENT-\(UUID().uuidString)"
        let outsideCPRDate = Date(timeIntervalSince1970: 1_800_000_000)
        try Data(outsideMarker.utf8).write(to: replacement.appendingPathComponent("notes.txt"))
        try Data("placeholder".utf8).write(to: replacement.appendingPathComponent("Song v1.cpr"))
        try fm.setAttributes(
            [.modificationDate: outsideCPRDate],
            ofItemAtPath: replacement.appendingPathComponent("Song v1.cpr").path
        )
        try Self.wav(seconds: Self.outsideSeconds).write(to: replacement.appendingPathComponent("Mixdown/Song mix.wav"))
        try Self.wav(seconds: Self.outsideSeconds).write(to: replacement.appendingPathComponent("Song bounce.wav"))
        var scanner = MusicArchiveScanner()
        var swapped = false
        scanner.raceHooks.entryListed = { [self] _ in
            guard !swapped else { return }
            swapped = true
            do {
                try fm.moveItem(at: song, to: base.appendingPathComponent("Parked Song"))
                try fm.moveItem(at: replacement, to: song)
            } catch {
                XCTFail("Could not swap song folder: \(error)")
            }
        }
        let result = try scanner.scan(roots: [root])
        XCTAssertTrue(swapped)
        guard let songResult = result.songs.first(where: { $0.originalFolderName == "Song" }) else {
            return
        }
        for preview in songResult.previewCandidates {
            XCTAssertNotEqual(
                preview.durationSeconds, Self.outsideSeconds,
                "read \(preview.filePath.path) from the swapped-in directory"
            )
        }
        XCTAssertNotEqual(songResult.sidecarNotes, outsideMarker, "read notes from the swapped-in directory")
        for version in songResult.projectVersions {
            XCTAssertNotEqual(version.modifiedAt, outsideCPRDate, "read version from the swapped-in directory")
        }
        XCTFail("swapped-in real directory must be discarded, not returned as Song")
    }

    private func swapSongForLink() {
        let fm = FileManager.default
        XCTAssertNoThrow(try fm.moveItem(at: song, to: base.appendingPathComponent("Parked Song")))
        XCTAssertNoThrow(try fm.createSymbolicLink(at: song, withDestinationURL: outside))
    }

    private func swapMixdownForLink() {
        let fm = FileManager.default
        let mixdown = song.appendingPathComponent("Mixdown")
        XCTAssertNoThrow(try fm.moveItem(at: mixdown, to: base.appendingPathComponent("Parked Mixdown")))
        XCTAssertNoThrow(try fm.createSymbolicLink(at: mixdown, withDestinationURL: outside))
    }

    private func assertNothingReadFromOutside(_ result: ScanResult, file: StaticString = #filePath, line: UInt = #line) throws {
        let songResult = try XCTUnwrap(result.songs.first { $0.originalFolderName == "Song" }, file: file, line: line)
        let inside = song.resolvingSymlinksInPath().path + "/"
        for preview in songResult.previewCandidates {
            XCTAssertNotEqual(preview.durationSeconds, Self.outsideSeconds, "read \(preview.filePath.path) outside the archive", file: file, line: line)
            XCTAssertTrue(preview.filePath.resolvingSymlinksInPath().path.hasPrefix(inside), preview.filePath.path, file: file, line: line)
        }
        for version in songResult.projectVersions {
            XCTAssertTrue(version.filePath.resolvingSymlinksInPath().path.hasPrefix(inside), version.filePath.path, file: file, line: line)
        }
        XCTAssertFalse(songResult.previewCandidates.contains { $0.fileName == "Stolen take.wav" }, file: file, line: line)
        XCTAssertFalse(songResult.projectVersions.contains { $0.fileName == "Stolen v9.cpr" }, file: file, line: line)
    }

    /// A 16-bit mono 44.1 kHz WAV header whose `data` chunk claims `seconds` of audio; only the
    /// header is written, which is all the duration reader looks at.
    private static func wav(seconds: Double) -> Data {
        let dataSize = UInt32(seconds * 88_200)
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF"); append32(36 + dataSize); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1); append32(44_100); append32(88_200)
        append16(2); append16(16)
        append("data"); append32(dataSize)
        return data
    }
}
