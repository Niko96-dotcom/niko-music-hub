@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// The catalog's lists, index and change rules, without a view model.
final class SongCatalogTests: XCTestCase {
    private func song(_ name: String, title: String? = nil) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: "/tmp/song-catalog/\(name)", isDirectory: true),
            originalFolderName: name,
            displayTitle: title ?? name
        )
    }

    private func sameStorage(_ left: [Song], _ right: [Song]) -> Bool {
        left.withUnsafeBufferPointer { l in right.withUnsafeBufferPointer { r in l.baseAddress == r.baseAddress } }
    }

    private func loaded(_ songs: [Song]) -> SongCatalog {
        var catalog = SongCatalog()
        _ = catalog.replaceAll(scanned: songs, visible: songs)
        return catalog
    }

    func testAFirstLoadListsNoChangedSongs() {
        var catalog = SongCatalog()

        let change = catalog.replaceAll(scanned: [song("A"), song("B")], visible: [song("A"), song("B")])

        XCTAssertTrue(change.visibleChanged && change.scannedChanged)
        XCTAssertEqual(change.changed, [], "new songs have no old value to compare")
        XCTAssertEqual(change.removed, [])
    }

    func testEqualListsGiveAnEmptyChangeAndKeepTheHeldStorage() {
        let songs = [song("A"), song("B")]
        var catalog = loaded(songs)
        let held = catalog.visible

        let change = catalog.replaceAll(scanned: songs.map { $0 }, visible: Array(songs))

        XCTAssertTrue(change.isEmpty)
        XCTAssertEqual(change, SongCatalogChange())
        XCTAssertTrue(sameStorage(catalog.visible, held), "an equal list must not replace the held one")
    }

    func testChangeNamesChangedAndNewSongsWithTheirOldValuesAndRemovedIDs() {
        let a = song("A"), b = song("B"), c = song("C")
        var catalog = loaded([a, b])
        let renamedB = song("B", title: "B renamed")

        let change = catalog.replaceAll(scanned: [renamedB, c], visible: [renamedB, c])

        XCTAssertTrue(change.scannedChanged)
        XCTAssertTrue(change.visibleChanged)
        XCTAssertEqual(change.changed, [SongCatalogChange.ChangedSong(before: b, after: renamedB)],
                       "a new song is not a changed song")
        XCTAssertEqual(change.removed, [a])
    }

    func testBaselineAndVisibleListChangeIndependently() {
        let a = song("A"), archived = song("Archived")
        var catalog = loaded([a])

        let shown = catalog.replaceAll(scanned: [a], visible: [a, archived])
        XCTAssertFalse(shown.scannedChanged)
        XCTAssertTrue(shown.visibleChanged)

        let baselineOnly = catalog.replaceAll(scanned: [], visible: [a, archived])
        XCTAssertTrue(baselineOnly.scannedChanged)
        XCTAssertFalse(baselineOnly.visibleChanged)
        XCTAssertEqual(baselineOnly.changed, [])
    }

    func testIndexFindsVisibleSongsIncludingProjectionsAndNotRemovedOnes() {
        let a = song("A"), b = song("B"), archived = song("Archived")
        var catalog = loaded([a, b])
        _ = catalog.replaceAll(scanned: [a], visible: [a, archived])

        XCTAssertEqual(catalog.song(id: a.id), a)
        XCTAssertEqual(catalog.song(id: archived.id), archived)
        XCTAssertNil(catalog.song(id: b.id))
        XCTAssertEqual(catalog.changedSongs(in: [a, b]), [b])
    }

    func testReplaceUpdatesBothListsAndTheIndex() {
        let a = song("A"), b = song("B")
        var catalog = loaded([a, b])
        let renamedA = song("A", title: "A renamed")

        let change = catalog.replace([renamedA], isArchiveOnly: { _ in false })

        XCTAssertEqual(catalog.visible, [renamedA, b])
        XCTAssertEqual(catalog.scanned, [renamedA, b])
        XCTAssertEqual(catalog.song(id: a.id), renamedA)
        XCTAssertEqual(change.changed, [SongCatalogChange.ChangedSong(before: a, after: renamedA)])
        XCTAssertTrue(change.scannedChanged)
        XCTAssertTrue(change.visibleChanged)
    }

    func testReplaceAppendsAMissingSongToTheBaselineUnlessItIsArchiveOnly() {
        let a = song("A"), fresh = song("Fresh"), archived = song("Archived")
        var catalog = loaded([a])

        let freshChange = catalog.replace([fresh], isArchiveOnly: { _ in false })
        XCTAssertEqual(catalog.scanned, [a, fresh])
        XCTAssertEqual(catalog.visible, [a], "the visible list follows the next projection, not a replace")
        XCTAssertTrue(freshChange.scannedChanged)
        XCTAssertFalse(freshChange.visibleChanged)

        let archivedChange = catalog.replace([archived], isArchiveOnly: { $0.id == archived.id })
        XCTAssertEqual(catalog.scanned, [a, fresh])
        XCTAssertTrue(archivedChange.isEmpty)
    }

    func testReplacingWithAnEqualSongChangesNothing() {
        let a = song("A")
        var catalog = loaded([a])

        XCTAssertTrue(catalog.replace([a], isArchiveOnly: { _ in false }).isEmpty)
    }

    func testSharingHeldValuesDedupesAndReusesUnchangedValues() {
        let a = song("A"), b = song("B")
        let catalog = loaded([a, b])
        let freshA = song("A")
        let renamedB = song("B", title: "B renamed")

        let shared = catalog.sharingHeldValues([freshA, renamedB, freshA])

        XCTAssertEqual(shared, [a, renamedB])
        XCTAssertTrue(sameStorage(catalog.sharingHeldValues([song("A"), song("B")]), catalog.scanned),
                      "an unchanged scan hands back the held baseline")
    }

    func testScannedAddingSortsANewSongByTitleAndReplacesAKnownOne() {
        let alpha = song("Alpha"), charlie = song("Charlie")
        let catalog = loaded([charlie, alpha])

        XCTAssertEqual(catalog.scannedAdding(song("Bravo")).map(\.originalFolderName), ["Alpha", "Bravo", "Charlie"])
        let renamedAlpha = song("Alpha", title: "Zulu")
        XCTAssertEqual(catalog.scannedAdding(renamedAlpha), [charlie, renamedAlpha], "a known song keeps its place")
    }

    func testRemoveAllReportsEveryVisibleID() {
        let a = song("A"), archived = song("Archived")
        var catalog = loaded([a])
        _ = catalog.replaceAll(scanned: [a], visible: [a, archived])

        let change = catalog.removeAll()

        XCTAssertEqual(change.removed, [a, archived])
        XCTAssertTrue(change.scannedChanged && change.visibleChanged)
        XCTAssertTrue(catalog.visible.isEmpty && catalog.scanned.isEmpty)
        XCTAssertNil(catalog.song(id: a.id))
        XCTAssertTrue(catalog.removeAll().isEmpty, "an empty catalog has nothing to remove")
    }
}
