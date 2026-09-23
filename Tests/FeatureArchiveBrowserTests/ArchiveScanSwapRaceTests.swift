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
