import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

@MainActor
final class ArchiveBrowseSearchInvalidationTests: XCTestCase {
    private func songs() -> [Song] {
        [
            Song(
                folderPath: URL(fileURLWithPath: "/fixture-only/Neon Hook"),
                originalFolderName: "Neon Hook",
                displayTitle: "Neon Hook",
                collaboratorNames: ["Maria Klein"]
            ),
            Song(
                folderPath: URL(fileURLWithPath: "/fixture-only/Ocean Drive"),
                originalFolderName: "Ocean Drive",
                displayTitle: "Ocean Drive",
                scanWarnings: ["missing preview"]
            ),
        ]
    }

    func testEmptyQueryKeepsIndexEmpty() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.songs = songs()
        model.recomputeBrowseResults()
        XCTAssertTrue(model.cachedSearchIndex.songs.isEmpty)
        XCTAssertEqual(model.filteredSongs.count, 2)
        XCTAssertFalse(model.isSearching)
    }

    func testFilterToggleWithEmptyQueryKeepsIndexEmptyAndAppliesFilter() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.songs = songs()
        model.recomputeBrowseResults()
        model.toggleBrowseFilter(.hasWarnings)
        XCTAssertTrue(model.cachedSearchIndex.songs.isEmpty)
        XCTAssertEqual(model.filteredSongs.map(\.displayTitle), ["Ocean Drive"])
        model.toggleBrowseFilter(.hasWarnings)
        XCTAssertTrue(model.cachedSearchIndex.songs.isEmpty)
        XCTAssertEqual(model.filteredSongs.count, 2)
    }

    func testActiveQuerySyncReflectsTitleEditAndPreservesOrder() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        // Folders intentionally distinct from titles so title invalidation is
        // observable (folder text would otherwise still match "neon").
        let titled = [
            Song(
                folderPath: URL(fileURLWithPath: "/fixture-only/Studio Alpha"),
                originalFolderName: "Studio Alpha",
                displayTitle: "Neon Hook",
                collaboratorNames: ["Maria Klein"]
            ),
            Song(
                folderPath: URL(fileURLWithPath: "/fixture-only/Studio Beta"),
                originalFolderName: "Studio Beta",
                displayTitle: "Ocean Drive",
                scanWarnings: ["missing preview"]
            ),
        ]
        model.songs = titled
        model.setSearchQuery("neon", immediate: true)
        XCTAssertEqual(model.filteredSongs.map(\.effectiveDisplayTitle), ["Neon Hook"])

        var updated = titled
        updated[0].virtualTitle = "Ocean Revised Title"
        model.songs = updated
        model.recomputeBrowseResults()
        // Old term no longer matches; the index now serves the edited title.
        XCTAssertTrue(model.filteredSongs.isEmpty)
        model.setSearchQuery("ocean revised", immediate: true)
        XCTAssertEqual(model.filteredSongs.map(\.id), [updated[0].id])
        XCTAssertFalse(model.searchMatchSummaries[updated[0].id, default: ""].isEmpty)
    }

    func testNonSearchEditReturnsFreshSongPreservingScores() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.songs = songs()
        model.setSearchQuery("neon", immediate: true)
        let beforeSummary = model.searchMatchSummaries
        XCTAssertEqual(model.filteredSongs.count, 1)

        var updated = songs()
        updated[0].collaboratorIDs = ["collab-2"]
        updated[0].previewSelectionMode = .manual
        model.songs = updated
        model.recomputeBrowseResults()
        XCTAssertEqual(model.filteredSongs.map(\.id), [updated[0].id])
        XCTAssertEqual(model.searchMatchSummaries, beforeSummary)
        XCTAssertEqual(model.filteredSongs.first?.collaboratorIDs, ["collab-2"])
        XCTAssertEqual(model.filteredSongs.first?.previewSelectionMode, .manual)
    }

    func testRemovalAndReorderReflectedWithActiveQuery() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.songs = songs()
        model.setSearchQuery("ocean", immediate: true)
        XCTAssertEqual(model.filteredSongs.map(\.displayTitle), ["Ocean Drive"])

        // Removal drops the match.
        model.songs = [songs()[0]]
        model.recomputeBrowseResults()
        XCTAssertTrue(model.filteredSongs.isEmpty)

        // Re-adding plus reorder still resolves the live Song value.
        let reordered = [songs()[1], songs()[0]]
        model.songs = reordered
        model.recomputeBrowseResults()
        XCTAssertEqual(model.filteredSongs.map(\.displayTitle), ["Ocean Drive"])
        XCTAssertEqual(model.cachedSearchIndex.songs.map(\.id), reordered.map(\.id))
    }

    func testActiveQueryKeepsRelevanceOrderOverSortMode() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.songs = songs()
        model.setSearchQuery("neon", immediate: true)
        let relevanceOrder = model.filteredSongs.map(\.id)
        model.setSortMode(.titleAZ)
        XCTAssertEqual(model.filteredSongs.map(\.id), relevanceOrder)
        // Filter narrows the already-ranked search without re-sorting.
        model.toggleBrowseFilter(.hasWarnings)
        XCTAssertTrue(model.filteredSongs.isEmpty)
        model.toggleBrowseFilter(.hasWarnings)
        XCTAssertEqual(model.filteredSongs.map(\.id), relevanceOrder)
    }

    func testBackgroundProjectorMatchesSynchronousProjection() async {
        let projector = ArchiveBrowseProjector()
        var state = ArchiveBrowseState(
            songs: songs(), showHiddenSongs: true, selectedShelf: .allSongs,
            selectedCollaboratorID: nil, searchQuery: "neon",
            browseFilter: [], sortMode: .recentCPR, skippedScanEntries: []
        )
        let first = await projector.project(state)
        XCTAssertEqual(first, ArchiveBrowseProjection.project(state))

        // Metadata edit invalidates the reused actor index.
        state.songs[0].virtualTitle = "Neon Revised"
        let second = await projector.project(state)
        XCTAssertEqual(second, ArchiveBrowseProjection.project(state))
        XCTAssertEqual(second?.filteredSongs.map(\.id), [state.songs[0].id])

        // Empty query stays cheap and matches the pure projection.
        state.searchQuery = ""
        let cleared = await projector.project(state)
        XCTAssertEqual(cleared, ArchiveBrowseProjection.project(state))
        XCTAssertFalse(cleared?.isSearching ?? true)
    }
}
