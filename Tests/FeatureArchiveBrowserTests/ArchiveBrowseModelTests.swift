import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

/// The browse owner on its own, over a song list the test controls: the empty query never
/// touches the search index, an active query keeps the reused index true to catalog edits, and
/// input changes, clearing and a root change behave as the browse page expects.
@MainActor
final class ArchiveBrowseModelTests: XCTestCase {
    /// The catalog and scan the browse model reads, and how often results were applied.
    private final class Source {
        var songs: [Song] = []
        var skipped: [SkippedScanEntry] = []
        var applied = 0
    }

    private func makeBrowse(_ source: Source, debounceNanoseconds: UInt64 = 200_000_000) -> ArchiveBrowseModel {
        ArchiveBrowseModel(
            refreshDriver: ArchiveBrowseRefreshDriver(debounceNanoseconds: debounceNanoseconds),
            source: ArchiveBrowseSource(
                songs: { source.songs },
                skippedEntries: { source.skipped },
                didApplyResults: { source.applied += 1 }
            )
        )
    }

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
        let source = Source()
        let model = makeBrowse(source)
        source.songs = songs()
        model.recompute()
        XCTAssertTrue(model.searchIndex.songs.isEmpty)
        XCTAssertEqual(model.filteredSongs.count, 2)
        XCTAssertFalse(model.isSearching)
    }

    func testFilterToggleWithEmptyQueryKeepsIndexEmptyAndAppliesFilter() {
        let source = Source()
        let model = makeBrowse(source)
        source.songs = songs()
        model.recompute()
        model.toggleBrowseFilter(.hasWarnings)
        XCTAssertTrue(model.searchIndex.songs.isEmpty)
        XCTAssertEqual(model.filteredSongs.map(\.displayTitle), ["Ocean Drive"])
        model.toggleBrowseFilter(.hasWarnings)
        XCTAssertTrue(model.searchIndex.songs.isEmpty)
        XCTAssertEqual(model.filteredSongs.count, 2)
    }

    func testActiveQuerySyncReflectsTitleEditAndPreservesOrder() {
        let source = Source()
        let model = makeBrowse(source)
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
        source.songs = titled
        model.setSearchQuery("neon", immediate: true)
        XCTAssertEqual(model.filteredSongs.map(\.effectiveDisplayTitle), ["Neon Hook"])

        var updated = titled
        updated[0].virtualTitle = "Ocean Revised Title"
        source.songs = updated
        model.recompute()
        // Old term no longer matches; the index now serves the edited title.
        XCTAssertTrue(model.filteredSongs.isEmpty)
        model.setSearchQuery("ocean revised", immediate: true)
        XCTAssertEqual(model.filteredSongs.map(\.id), [updated[0].id])
        XCTAssertFalse(model.searchMatchSummaries[updated[0].id, default: ""].isEmpty)
    }

    func testNonSearchEditReturnsFreshSongPreservingScores() {
        let source = Source()
        let model = makeBrowse(source)
        source.songs = songs()
        model.setSearchQuery("neon", immediate: true)
        let beforeSummary = model.searchMatchSummaries
        XCTAssertEqual(model.filteredSongs.count, 1)

        var updated = songs()
        updated[0].collaboratorIDs = ["collab-2"]
        updated[0].previewSelectionMode = .manual
        source.songs = updated
        model.recompute()
        XCTAssertEqual(model.filteredSongs.map(\.id), [updated[0].id])
        XCTAssertEqual(model.searchMatchSummaries, beforeSummary)
        XCTAssertEqual(model.filteredSongs.first?.collaboratorIDs, ["collab-2"])
        XCTAssertEqual(model.filteredSongs.first?.previewSelectionMode, .manual)
    }

    func testRemovalAndReorderReflectedWithActiveQuery() {
        let source = Source()
        let model = makeBrowse(source)
        source.songs = songs()
        model.setSearchQuery("ocean", immediate: true)
        XCTAssertEqual(model.filteredSongs.map(\.displayTitle), ["Ocean Drive"])

        // Removal drops the match.
        source.songs = [songs()[0]]
        model.recompute()
        XCTAssertTrue(model.filteredSongs.isEmpty)

        // Re-adding plus reorder still resolves the live Song value.
        let reordered = [songs()[1], songs()[0]]
        source.songs = reordered
        model.recompute()
        XCTAssertEqual(model.filteredSongs.map(\.displayTitle), ["Ocean Drive"])
        XCTAssertEqual(model.searchIndex.songs.map(\.id), reordered.map(\.id))
    }

    func testActiveQueryKeepsRelevanceOrderOverSortMode() {
        let source = Source()
        let model = makeBrowse(source)
        source.songs = songs()
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

    func testClearSearchResetsQueryAndResults() {
        let source = Source()
        let model = makeBrowse(source)
        source.songs = songs()
        model.recompute()
        let unfilteredShelf = model.filteredSongs
        XCTAssertEqual(unfilteredShelf.count, 2)

        model.setSearchQuery("Neon Hook", immediate: true)
        XCTAssertEqual(model.searchQuery, "Neon Hook")
        XCTAssertEqual(model.filteredSongs.map(\.displayTitle), ["Neon Hook"])

        model.clearSearch()
        XCTAssertEqual(model.searchQuery, "")
        XCTAssertEqual(model.filteredSongs.map(\.id), unfilteredShelf.map(\.id))
        XCTAssertFalse(model.isSearching)
    }

    func testEveryApplyReportsBackSoTheSelectionCanFollow() {
        let source = Source()
        let model = makeBrowse(source)
        source.songs = songs()

        model.recompute()
        model.setSortMode(.titleAZ)
        model.setSearchQuery("neon", immediate: true)

        XCTAssertEqual(source.applied, 3)
    }

    func testTheCollaboratorShelfStartsOnTheDefaultCollaboratorOnlyWhenNoneIsChosen() {
        let source = Source()
        let model = makeBrowse(source)

        model.selectShelf(.byCollaborator, defaultCollaboratorID: "first")
        XCTAssertEqual(model.selectedCollaboratorID, "first")

        model.setSelectedCollaboratorID("second")
        model.selectShelf(.allSongs, defaultCollaboratorID: "first")
        model.selectShelf(.byCollaborator, defaultCollaboratorID: "first")
        XCTAssertEqual(model.selectedCollaboratorID, "second")
    }

    func testARootChangeRestoresTheDefaultsWithoutRecomputing() {
        let source = Source()
        let model = makeBrowse(source)
        source.songs = songs()
        model.setSearchQuery("neon", immediate: true)
        model.setSortMode(.titleAZ)
        model.toggleBrowseFilter(.hasWarnings)
        model.toggleShowHiddenSongs()
        let applied = source.applied

        model.clearForRootChange()

        XCTAssertEqual(model.searchQuery, "")
        XCTAssertEqual(model.sortMode, .recentCPR)
        XCTAssertEqual(model.browseFilter, [])
        XCTAssertFalse(model.showHiddenSongs)
        XCTAssertEqual(model.selectedShelf, .allSongs)
        XCTAssertTrue(model.filteredSongs.isEmpty)
        XCTAssertFalse(model.isSearching)
        XCTAssertTrue(model.searchIndex.songs.isEmpty, "a new index for the new roots")
        XCTAssertEqual(source.applied, applied, "the catalog's clear edit recomputes, not the reset")
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
