import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

@MainActor
final class ArchiveSearchClearTests: XCTestCase {
    func testClearSearchResetsQueryAndResults() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.songs = [
            Song(
                folderPath: URL(fileURLWithPath: "/fixture-only/Neon Hook"),
                originalFolderName: "Neon Hook",
                displayTitle: "Neon Hook"
            ),
            Song(
                folderPath: URL(fileURLWithPath: "/fixture-only/Ocean Drive"),
                originalFolderName: "Ocean Drive",
                displayTitle: "Ocean Drive"
            ),
        ]
        model.recomputeBrowseResults()
        let unfilteredShelf = model.filteredSongs
        XCTAssertEqual(unfilteredShelf.count, 2)

        model.setSearchQuery("Neon Hook", immediate: true)
        XCTAssertEqual(model.searchQuery, "Neon Hook")
        XCTAssertEqual(model.filteredSongs.map(\.displayTitle), ["Neon Hook"])

        model.clearSearch()
        XCTAssertEqual(model.searchQuery, "")
        XCTAssertEqual(model.filteredSongs.map(\.id), unfilteredShelf.map(\.id))
        XCTAssertEqual(Set(model.filteredSongs.map(\.id)), Set(model.songs.map(\.id)))
        XCTAssertFalse(model.isSearching)
    }
}
