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
}
