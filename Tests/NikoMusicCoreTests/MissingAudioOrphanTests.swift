import XCTest
@testable import NikoMusicCore

final class MissingAudioOrphanTests: XCTestCase {
    func testListsOrphanAudioPathsPerSong() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubOrphan-\(UUID().uuidString)", isDirectory: true)
        let songFolder = root.appendingPathComponent("Song", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songFolder.appendingPathComponent("Song.cpr").path,
            contents: Data("fixture".utf8)
        )
        FileManager.default.createFile(
            atPath: songFolder.appendingPathComponent("orphan.wav").path,
            contents: Data("fixture".utf8)
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try CubaseArchiveScanner().scan(roots: [root])
        let song = try XCTUnwrap(result.songs.first)
        let report = ArchiveIntelligence.missingAudioReport(songs: result.songs)
        let orphans = try XCTUnwrap(report.orphanAudioBySongID[song.id])
        XCTAssertTrue(orphans.contains("orphan.wav"))
    }

    func testBoundedReportKeepsSummaryWithoutEnumeratingOrphanNames() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubOrphanSummary-\(UUID().uuidString)", isDirectory: true)
        let songFolder = root.appendingPathComponent("Song", isDirectory: true)
        let secondSongFolder = root.appendingPathComponent("Second Song", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSongFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for name in ["one.wav", "two.wav", "three.wav"] {
            FileManager.default.createFile(
                atPath: songFolder.appendingPathComponent(name).path,
                contents: Data("fixture".utf8)
            )
        }
        FileManager.default.createFile(
            atPath: secondSongFolder.appendingPathComponent("four.wav").path,
            contents: Data("fixture".utf8)
        )
        let song = Song(
            folderPath: songFolder,
            originalFolderName: "Song",
            displayTitle: "Song"
        )
        let secondSong = Song(
            folderPath: secondSongFolder,
            originalFolderName: "Second Song",
            displayTitle: "Second Song"
        )
        let songs = [song, secondSong]

        let complete = ArchiveIntelligence.missingAudioReport(songs: songs)
        XCTAssertEqual(complete.orphanAudioBySongID.values.flatMap { $0 }.count, 4)

        let capped = ArchiveIntelligence.missingAudioReport(
            songs: songs,
            maximumRetainedOrphanAudioPaths: 2
        )
        XCTAssertEqual(capped.orphanAudioBySongID.values.flatMap { $0 }.count, 2)

        let summary = ArchiveIntelligence.missingAudioReport(
            songs: songs,
            maximumRetainedOrphanAudioPaths: 0
        )
        XCTAssertEqual(summary.noPreview, ["Song", "Second Song"])
        XCTAssertEqual(summary.noCPR, ["Song", "Second Song"])
        XCTAssertTrue(summary.orphanAudioBySongID.isEmpty)
    }

    func testSymlinkedSongRootYieldsNoOrphans() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubOrphanLinkRoot-\(UUID().uuidString)", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        let songFolder = base.appendingPathComponent("Song", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: outside.appendingPathComponent("secret.wav").path,
            contents: Data("fixture".utf8)
        )
        try FileManager.default.createSymbolicLink(atPath: songFolder.path, withDestinationPath: outside.path)
        defer { try? FileManager.default.removeItem(at: base) }

        let song = Song(folderPath: songFolder, originalFolderName: "Song", displayTitle: "Song")
        let report = ArchiveIntelligence.missingAudioReport(songs: [song])
        XCTAssertNil(report.orphanAudioBySongID[song.id])
    }

    func testNestedSymlinksDoNotLeakOutsideNames() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubOrphanNested-\(UUID().uuidString)", isDirectory: true)
        let songFolder = base.appendingPathComponent("Song", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songFolder.appendingPathComponent("orphan.wav").path,
            contents: Data("fixture".utf8)
        )
        FileManager.default.createFile(
            atPath: outside.appendingPathComponent("secret.wav").path,
            contents: Data("fixture".utf8)
        )
        try FileManager.default.createSymbolicLink(
            atPath: songFolder.appendingPathComponent("LinkedDir").path,
            withDestinationPath: outside.path
        )
        try FileManager.default.createSymbolicLink(
            atPath: songFolder.appendingPathComponent("Escape.wav").path,
            withDestinationPath: outside.appendingPathComponent("secret.wav").path
        )
        defer { try? FileManager.default.removeItem(at: base) }

        let song = Song(folderPath: songFolder, originalFolderName: "Song", displayTitle: "Song")
        let report = ArchiveIntelligence.missingAudioReport(songs: [song])
        let orphans = try XCTUnwrap(report.orphanAudioBySongID[song.id])
        XCTAssertTrue(orphans.contains("orphan.wav"))
        XCTAssertFalse(orphans.contains("secret.wav"))
        XCTAssertFalse(orphans.contains("Escape.wav"))
    }

    func testSwappedSongBaseIsRejected() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubOrphanSwap-\(UUID().uuidString)", isDirectory: true)
        let songFolder = base.appendingPathComponent("Song", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: outside.appendingPathComponent("secret.wav").path,
            contents: Data("fixture".utf8)
        )
        // Simulate a swap between enumeration and report: replace the real folder
        // with a link to outside before the report walks it.
        try FileManager.default.removeItem(at: songFolder)
        try FileManager.default.createSymbolicLink(atPath: songFolder.path, withDestinationPath: outside.path)
        defer { try? FileManager.default.removeItem(at: base) }

        let song = Song(folderPath: songFolder, originalFolderName: "Song", displayTitle: "Song")
        let report = ArchiveIntelligence.missingAudioReport(songs: [song])
        XCTAssertNil(report.orphanAudioBySongID[song.id])
    }

    func testCancelledEnumerationReturnsEmpty() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubOrphanCancel-\(UUID().uuidString)", isDirectory: true)
        let songFolder = base.appendingPathComponent("Song", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songFolder.appendingPathComponent("orphan.wav").path,
            contents: Data("fixture".utf8)
        )
        defer { try? FileManager.default.removeItem(at: base) }

        let song = Song(folderPath: songFolder, originalFolderName: "Song", displayTitle: "Song")
        let task = Task<MissingAudioReport, Never> {
            try? await Task.sleep(nanoseconds: 50_000_000)
            return ArchiveIntelligence.missingAudioReport(songs: [song])
        }
        task.cancel()
        let report = await task.value
        XCTAssertTrue(report.orphanAudioBySongID.isEmpty)
    }
}
