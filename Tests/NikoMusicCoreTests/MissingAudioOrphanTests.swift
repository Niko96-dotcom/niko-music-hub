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
}
