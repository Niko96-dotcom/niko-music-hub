import AppCore
import Combine
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// What `applyCatalogEdit(_:)` does around a catalog write, seen through the view model.
@MainActor
final class ArchiveCatalogEditTests: XCTestCase {
    private func song(_ name: String, title: String? = nil) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: "/tmp/catalog-edit/\(name)", isDirectory: true),
            originalFolderName: name,
            displayTitle: title ?? name
        )
    }

    private func makeModel(_ songs: [Song]) -> ArchiveBrowserViewModel {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make(), archiveRootWatcher: NoopArchiveRootWatcher())
        model.applyCatalogEdit(.load(songs))
        return model
    }

    /// Replacing a song with an equal value changes nothing, so nothing publishes (B6).
    func testReplacingWithAnEqualSongPublishesNothing() {
        let neon = song("A", title: "Neon Hook")
        let model = makeModel([neon, song("B", title: "Ocean Drive")])
        var publications = 0
        let cancellable = model.objectWillChange.sink { _ in publications += 1 }
        defer { withExtendedLifetime(cancellable) {} }

        let change = model.applyCatalogEdit(.replace([neon]))

        XCTAssertTrue(change.isEmpty)
        XCTAssertEqual(publications, 0)
    }

    /// An edited song that stays in the filtered list stays selected with its new value.
    func testEditedSelectedSongStaysSelectedWithItsNewValue() {
        let neon = song("A", title: "Neon Hook")
        let model = makeModel([neon, song("B", title: "Ocean Drive")])
        model.setSearchQuery("neon", immediate: true)
        model.selectSong(neon)

        let renamed = song("A", title: "Neon Hook (Remix)")
        model.applyCatalogEdit(.replace([renamed]))

        XCTAssertEqual(model.selectedSong, renamed)
        XCTAssertEqual(model.filteredSongs, [renamed])
    }

    /// An edit that moves the selected song out of the filtered list deselects it:
    /// the browse recompute reconciles the selection, as before the catalog writer.
    func testEditThatMovesTheSelectedSongOutOfTheFilterDeselectsIt() {
        let neon = song("A", title: "Neon Hook")
        let model = makeModel([neon, song("B", title: "Ocean Drive")])
        model.setSearchQuery("neon", immediate: true)
        model.selectSong(neon)

        model.applyCatalogEdit(.replace([song("A", title: "Sunset")]))

        XCTAssertNil(model.selectedSong)
        XCTAssertEqual(model.filteredSongs, [])
    }
}
