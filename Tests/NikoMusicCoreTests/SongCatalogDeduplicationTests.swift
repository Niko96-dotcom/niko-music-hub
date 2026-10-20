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

    func testUniqueCatalogIsReturnedAsItIsWithTheSameStorage() {
        let songs = (0..<50).map {
            Song(folderPath: URL(fileURLWithPath: "/tmp/dedupe-same/\($0)"), originalFolderName: "S\($0)", displayTitle: "S\($0)")
        }
        let result = SongCatalogDeduplicator.uniqueByID(songs)
        XCTAssertEqual(result, songs)
        XCTAssertTrue(songs.withUnsafeBufferPointer { a in result.withUnsafeBufferPointer { b in a.baseAddress == b.baseAddress } })
    }

    func testRepeatsAnywhereKeepTheFirstOccurrenceInCatalogOrder() {
        func song(_ name: String, note: String? = nil) -> Song {
            Song(folderPath: URL(fileURLWithPath: "/tmp/dedupe-order/\(name)"), originalFolderName: name, displayTitle: name, appNote: note)
        }
        let input = [song("a"), song("b", note: "first b"), song("c"), song("b", note: "second b"), song("d"), song("a", note: "second a"), song("e")]
        let result = SongCatalogDeduplicator.uniqueByID(input)
        XCTAssertEqual(result.map(\.originalFolderName), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(result[1].appNote, "first b")
        XCTAssertNil(result[0].appNote)
        XCTAssertEqual(SongCatalogDeduplicator.uniqueByID([song("x"), song("x")]).count, 1)
        XCTAssertEqual(SongCatalogDeduplicator.uniqueByID([]).count, 0)
    }
}
