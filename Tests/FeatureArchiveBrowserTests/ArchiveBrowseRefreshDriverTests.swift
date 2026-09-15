import Combine
import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

@MainActor
final class ArchiveBrowseRefreshDriverTests: XCTestCase {
    func testResultCountTracksAppliedSearchAndClears() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.songs = state("").songs
        model.recomputeBrowseResults()
        XCTAssertNil(model.searchResultCountText)
        model.setSearchQuery("neon")
        XCTAssertNil(model.searchResultCountText)
        model.recomputeBrowseResults()
        XCTAssertTrue(model.isSearching)
        XCTAssertEqual(model.searchResultCountText, "1 result")
        model.setSearchQuery("zzzzzzzzzzzz")
        model.recomputeBrowseResults()
        XCTAssertEqual(model.searchResultCountText, "0 results")
        model.statusMessage = "Scan needs attention"
        model.setSearchQuery("")
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.searchResultCountText)
        XCTAssertEqual(model.filteredSongs.count, 2)
        XCTAssertEqual(model.statusMessage, "Scan needs attention")
    }

    func testTypingPublishesTextWithoutInvalidatingArchiveUntilResultsApply() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.songs = state("").songs
        model.filteredSongs = model.songs
        var archiveChanges = 0
        var enteredText: [String] = []
        let archiveSubscription = model.objectWillChange.sink { archiveChanges += 1 }
        let textSubscription = model.searchInput.$query.dropFirst().sink { enteredText.append($0) }
        model.setSearchQuery("neon")
        model.setSearchQuery("neon hook")
        XCTAssertEqual(archiveChanges, 0)
        XCTAssertEqual(enteredText, ["neon", "neon hook"])
        XCTAssertEqual(model.searchQuery, "neon hook")
        XCTAssertEqual(model.filteredSongs.count, 2)
        model.recomputeBrowseResults()
        XCTAssertGreaterThan(archiveChanges, 0)
        XCTAssertEqual(model.filteredSongs.map(\.displayTitle), ["Neon Hook"])
        withExtendedLifetime((archiveSubscription, textSubscription)) {}
    }

    func testCanceledInFlightSearchCannotPublish() async throws {
        let projector = SuspendedBrowseProjector()
        let driver = ArchiveBrowseRefreshDriver(debounceNanoseconds: 0, projector: projector)
        let stale = expectation(description: "Canceled search must not publish")
        stale.isInverted = true
        driver.scheduleDebouncedBrowseRecompute(snapshot: { self.state("neon") }, apply: { _ in stale.fulfill() })
        try await waitForCalls(1, projector: projector)
        driver.cancelPendingDebounce()
        await projector.complete(0)
        let waitResult = await XCTWaiter.fulfillment(of: [stale], timeout: 0.05)
        XCTAssertEqual(waitResult, .completed)
    }

    func testNewSearchWinsEvenWhenOldSearchCompletesLast() async throws {
        let projector = SuspendedBrowseProjector()
        let driver = ArchiveBrowseRefreshDriver(debounceNanoseconds: 0, projector: projector)
        var applied: [ArchiveBrowseResult] = []
        driver.scheduleDebouncedBrowseRecompute(snapshot: { self.state("neon") }, apply: { applied.append($0) })
        try await waitForCalls(1, projector: projector)
        let ready = expectation(description: "Latest search published")
        driver.scheduleDebouncedBrowseRecompute(snapshot: { self.state("ocean") }, apply: {
            applied.append($0); ready.fulfill()
        })
        try await waitForCalls(2, projector: projector)
        await projector.complete(1)
        let waitResult = await XCTWaiter.fulfillment(of: [ready], timeout: 1)
        XCTAssertEqual(waitResult, .completed)
        await projector.complete(0)
        // Let the canceled continuation return through the main-actor driver.
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(applied, [ArchiveBrowseProjection.project(state("ocean"))])
    }

    func testSnapshotUsesInputsAtEndOfDebounce() async throws {
        let projector = SuspendedBrowseProjector()
        let driver = ArchiveBrowseRefreshDriver(debounceNanoseconds: 20_000_000, projector: projector)
        var current = state("neon")
        driver.scheduleDebouncedBrowseRecompute(snapshot: { current }, apply: { _ in })
        current.searchQuery = "ocean"
        current.songs[1].virtualTitle = "Ocean revised"
        try await waitForCalls(1, projector: projector)
        let captured = await projector.states[0]
        XCTAssertEqual(captured, current)
        driver.cancelPendingDebounce()
        await projector.complete(0)
    }

    func testBackgroundProjectorPreservesFullProjection() async {
        let projector = ArchiveBrowseProjector()
        for query in ["", "neon", "ocean", "not-present"] {
            var input = state(query)
            input.songs[0].isIgnored = true
            for includeHidden in [false, true] {
                input.showHiddenSongs = includeHidden
                let actual = await projector.project(input)
                XCTAssertEqual(actual, ArchiveBrowseProjection.project(input))
            }
        }
    }

    func testImmediateClearAndRootResetSupersedePendingLiveSearch() async throws {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make(), browseSearchDebounceNanoseconds: 0)
        model.songs = state("").songs
        model.filteredSongs = model.songs
        model.setSearchQuery("neon")
        model.setSearchQuery("", immediate: true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(Set(model.filteredSongs.map(\.id)), Set(model.songs.map(\.id)))
        model.setSearchQuery("ocean")
        model.recomputeBrowseResults()
        XCTAssertEqual(model.searchResultCountText, "1 result")
        model.clearScanResults()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(model.filteredSongs.isEmpty)
        XCTAssertTrue(model.searchMatchSummaries.isEmpty)
        XCTAssertEqual(model.searchQuery, "")
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.searchResultCountText)
    }

    private func waitForCalls(_ count: Int, projector: SuspendedBrowseProjector) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while await projector.states.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        let actual = await projector.states.count
        XCTAssertEqual(actual, count)
    }

    private func state(_ query: String) -> ArchiveBrowseState {
        let songs = ["Neon Hook", "Ocean Drive"].map {
            Song(folderPath: URL(fileURLWithPath: "/fixture-only/\($0)"), originalFolderName: $0, displayTitle: $0)
        }
        return ArchiveBrowseState(songs: songs, showHiddenSongs: false, selectedShelf: .allSongs,
            selectedCollaboratorID: nil, searchQuery: query, browseFilter: [], sortMode: .recentCPR, skippedScanEntries: [])
    }
}

private actor SuspendedBrowseProjector: ArchiveBrowseProjecting {
    private(set) var states: [ArchiveBrowseState] = []
    private var pending: [Int: CheckedContinuation<ArchiveBrowseResult?, Never>] = [:]

    func project(_ state: ArchiveBrowseState) async -> ArchiveBrowseResult? {
        let index = states.count
        states.append(state)
        return await withCheckedContinuation { pending[index] = $0 }
    }

    func complete(_ index: Int) {
        pending.removeValue(forKey: index)?.resume(returning: ArchiveBrowseProjection.project(states[index]))
    }
}
