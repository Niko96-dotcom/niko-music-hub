import Foundation
import NikoMusicCore
import XCTest

final class SongCatalogDeduplicationTests: XCTestCase {
    func testDeduplicatorPreservesFirstOccurrenceAndOrder() {
        let first = song(path: "/tmp/song-a", title: "First")
        let duplicate = song(path: "/tmp/song-a", title: "Duplicate")
        let second = song(path: "/tmp/song-b", title: "Second")

        let result = SongCatalogDeduplicator.uniqueByID([first, duplicate, second])

        XCTAssertEqual(result.map(\.effectiveDisplayTitle), ["First", "Second"])
    }

    func testMissingAudioReportAcceptsDuplicateSongIDsWithoutTrapping() {
        let song = song(path: "/path/that/does/not/exist", title: "Song")

        let report = ArchiveIntelligence.missingAudioReport(songs: [song, song])

        XCTAssertEqual(report.noPreview, ["Song"])
        XCTAssertEqual(report.noCPR, ["Song"])
        XCTAssertTrue(report.orphanAudioBySongID.isEmpty)
    }

    private func song(path: String, title: String) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: path, isDirectory: true),
            originalFolderName: title,
            displayTitle: title
        )
    }
}
