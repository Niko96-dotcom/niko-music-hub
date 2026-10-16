import Foundation
import NikoMusicCore
import XCTest

final class ArchiveIntelligenceDuplicateHintTests: XCTestCase {
    func testDuplicateHintsWithEqualCountsAreOrderedByNormalizedTitle() {
        // Many equal-count groups make the dictionary's per-run order visible
        // without a stable secondary key. The input order is shuffled on each
        // run so the expected order cannot come from insertion order either.
        let titles = (0..<40).map { index in
            String(format: "Song %02d", index)
        }
        var songs: [Song] = []
        for title in titles {
            songs.append(song(path: "/tmp/\(title)-a", title: title))
            songs.append(song(path: "/tmp/\(title)-b", title: title))
        }
        songs.append(song(path: "/tmp/triple-1", title: "Triple"))
        songs.append(song(path: "/tmp/triple-2", title: "Triple"))
        songs.append(song(path: "/tmp/triple-3", title: "Triple"))
        songs.shuffle()

        let hints = ArchiveIntelligence.duplicateSongHints(songs: songs)

        let expected = ["triple"] + titles.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        XCTAssertEqual(hints.map(\.normalizedTitle), expected)
        XCTAssertEqual(hints.first?.displayTitles.count, 3)

        let repeated = ArchiveIntelligence.duplicateSongHints(songs: songs.shuffled())
        XCTAssertEqual(repeated.map(\.normalizedTitle), expected)
    }

    private func song(path: String, title: String) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: path, isDirectory: true),
            originalFolderName: title,
            displayTitle: title
        )
    }
}
