import Foundation
import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

/// Analytics liveness: catalog edits while the page is open refresh the
/// snapshot; browse typing/selection stay cheap and off-analytics stays lazy.
@MainActor
final class ArchiveAnalyticsTests: XCTestCase {
    private func song(_ name: String, status: ProjectWorkflowStatus? = nil) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: "/fixture-only/\(name)"),
            originalFolderName: name,
            displayTitle: name,
            workflowStatus: status
        )
    }

    private final class HistoryCountingStore: SongUserMetadataStoring, WorkflowStatusHistoryReading, @unchecked Sendable {
        private let lock = NSLock()
        private var reads = 0

        var historyReadCount: Int { lock.withLock { reads } }

        func loadAll() throws -> [String: SongUserMetadata] { [:] }
        func upsert(_ metadata: SongUserMetadata) throws {}
        func upsertAll(_ metadata: [SongUserMetadata]) throws {}
        func loadAllStatusHistory() throws -> [WorkflowStatusChange] {
            lock.withLock { reads += 1 }
            return []
        }

        func statusHistory(forSongID songID: String) throws -> [WorkflowStatusChange] { [] }
    }

    func testCatalogAppendWhileAnalyticsOpenUpdatesSnapshot() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.applyCatalogEdit(.load([song("Alpha", status: .prod), song("Beta", status: .song)]))
        model.showAnalytics()
        XCTAssertTrue(model.viewMode == .analytics)
        XCTAssertEqual(model.analyticsSnapshot?.overview.totalSongs, 2)

        do {
            var updated = model.songs
            updated.append(song("Gamma", status: .done))
            model.applyCatalogEdit(.load(updated))
        }

        XCTAssertTrue(model.viewMode == .analytics, "must stay on the analytics page")
        XCTAssertEqual(model.analyticsSnapshot?.overview.totalSongs, 3)
        XCTAssertEqual(model.analyticsSnapshot?.overview.finished, 1)
    }

    func testStatusChangeWhileAnalyticsOpenUpdatesSnapshot() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.applyCatalogEdit(.load([song("Alpha", status: .prod), song("Beta", status: .song)]))
        model.showAnalytics()
        XCTAssertEqual(model.analyticsSnapshot?.overview.finished, 0)

        do {
            var updated = model.songs
            updated[0].workflowStatus = .done
            model.applyCatalogEdit(.load(updated))
        }

        XCTAssertEqual(model.analyticsSnapshot?.overview.finished, 1)
        XCTAssertEqual(model.analyticsSnapshot?.overview.totalSongs, 2)
    }

    func testCatalogUpdatesStayLazyOutsideAnalytics() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.applyCatalogEdit(.load([song("Alpha")]))
        XCTAssertNil(model.analyticsSnapshot, "no snapshot before entering analytics")

        do {
            var updated = model.songs
            updated.append(song("Beta"))
            model.applyCatalogEdit(.load(updated))
        }
        XCTAssertNil(model.analyticsSnapshot, "catalog churn outside analytics must stay lazy")

        model.showAnalytics()
        XCTAssertEqual(model.analyticsSnapshot?.overview.totalSongs, 2)

        model.viewMode = .board
        do {
            var updated = model.songs
            updated.append(song("Gamma"))
            model.applyCatalogEdit(.load(updated))
        }
        XCTAssertEqual(
            model.analyticsSnapshot?.overview.totalSongs, 2,
            "leaving analytics must resume lazy snapshots until re-entry"
        )
    }

    /// New Song is one catalog edit, so the open analytics page refreshes once (B4).
    func testNewSongWhileAnalyticsOpenRefreshesOnce() throws {
        unsetenv("NIKO_MUSIC_HUB_FIXTURE_ROOT")
        setenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN", "1", 1)
        defer { unsetenv("NIKO_MUSIC_HUB_DRY_RUN_OPEN") }
        let archiveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-new-song-\(UUID().uuidString)", isDirectory: true)
        let draftRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-new-song-drafts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: archiveRoot)
            try? FileManager.default.removeItem(at: draftRoot)
        }
        let store = HistoryCountingStore()
        let model = ArchiveBrowserViewModel(context: TestToolContext.make(), songMetadataStore: store)
        model.roots = [archiveRoot]
        model.applyCatalogEdit(.load([song("Neon Hook")]))
        model.showAnalytics()
        let baselineReads = store.historyReadCount

        let created = try model.createNewSong(request: NewSongRequest(name: "Fresh Draft", root: draftRoot, appNote: "test"))

        XCTAssertEqual(store.historyReadCount, baselineReads + 1, "one catalog edit, one analytics refresh")
        XCTAssertEqual(model.songs.filter { $0.id == created.id }.count, 1)
    }

    /// Removing a collaborator from several songs is one catalog edit, so the open
    /// analytics page refreshes once, not once per song (B3).
    func testCollaboratorRemovalFromThreeSongsRefreshesOnce() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-collaborator-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let store = HistoryCountingStore()
        let model = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: store,
            collaboratorStore: try SQLiteCollaboratorStore(databaseURL: databaseURL)
        )
        let jamie = try XCTUnwrap(model.upsertCollaborator(name: "Jamie"))
        model.applyCatalogEdit(.load([song("One"), song("Two"), song("Three")]))
        for song in model.songs {
            model.assignCollaborators(to: song, collaboratorIDs: [jamie.id])
        }
        XCTAssertEqual(model.songs.map(\.collaboratorIDs), [[jamie.id], [jamie.id], [jamie.id]])
        model.showAnalytics()
        let baselineReads = store.historyReadCount

        model.requestRemoveCollaborator(jamie)
        model.confirmRemoveCollaborator()

        XCTAssertEqual(model.songs.map(\.collaboratorIDs), [[], [], []])
        XCTAssertEqual(store.historyReadCount, baselineReads + 1, "one catalog edit, one analytics refresh")
    }

    func testSearchAndSelectionWhileAnalyticsOpenAvoidHistoryReads() {
        let store = HistoryCountingStore()
        let model = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: store
        )
        model.applyCatalogEdit(.load([song("Neon Hook"), song("Ocean Drive")]))
        model.showAnalytics()
        let baselineReads = store.historyReadCount
        XCTAssertGreaterThanOrEqual(baselineReads, 1)

        model.setSearchQuery("neon", immediate: true)
        model.toggleBrowseFilter(.hasWarnings)
        if let first = model.songs.first {
            model.selectSong(first)
        }

        XCTAssertEqual(
            store.historyReadCount, baselineReads,
            "typing, filtering, and selection must not re-read status history"
        )

        do {
            var updated = model.songs
            updated.append(song("Third Song"))
            model.applyCatalogEdit(.load(updated))
        }
        XCTAssertEqual(store.historyReadCount, baselineReads + 1, "actual catalog updates must refresh")
        XCTAssertEqual(model.analyticsSnapshot?.overview.totalSongs, 3)
    }
}
