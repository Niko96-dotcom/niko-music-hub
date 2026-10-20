import Foundation
@testable import NikoMusicCore
import XCTest

final class SongDifferenceTests: XCTestCase {
    private func song(_ index: Int, note: String? = nil) -> Song {
        Song(folderPath: URL(fileURLWithPath: "/tmp/difference/\(index)", isDirectory: true),
             originalFolderName: "S\(index)", displayTitle: "S\(index)", appNote: note)
    }

    func testEqualSongsThatShareNoStorageAreNotDifferent() {
        let held = Dictionary(uniqueKeysWithValues: (0..<2_000).map { (song($0).id, song($0)) })
        XCTAssertEqual((0..<2_000).map { song($0) }.songsDiffering(from: held), [])
    }

    func testChangedAndNewSongsAreReturnedInOrder() {
        let held = Dictionary(uniqueKeysWithValues: (0..<2_000).map { (song($0).id, song($0)) })
        var incoming = (0..<2_000).map { song($0) }
        incoming[1_500] = song(1_500, note: "edited")
        incoming[3] = song(3, note: "edited")
        incoming.append(song(5_000))
        XCTAssertEqual(incoming.songsDiffering(from: held).map(\.id), [song(3).id, song(1_500).id, song(5_000).id])
    }

    func testEverySongIsNewAgainstAnEmptyCatalog() {
        let incoming = (0..<10).map { song($0) }
        XCTAssertEqual(incoming.songsDiffering(from: [:]), incoming)
    }
}
