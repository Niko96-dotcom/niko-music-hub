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
        model.mutateCatalog {
            model.songs = [song("Alpha", status: .prod), song("Beta", status: .song)]
        }
        model.showAnalytics()
        XCTAssertTrue(model.viewMode == .analytics)
        XCTAssertEqual(model.analyticsSnapshot?.overview.totalSongs, 2)

        model.mutateCatalog {
            var updated = model.songs
            updated.append(song("Gamma", status: .done))
            model.songs = updated
        }

        XCTAssertTrue(model.viewMode == .analytics, "must stay on the analytics page")
        XCTAssertEqual(model.analyticsSnapshot?.overview.totalSongs, 3)
        XCTAssertEqual(model.analyticsSnapshot?.overview.finished, 1)
    }

    func testStatusChangeWhileAnalyticsOpenUpdatesSnapshot() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.mutateCatalog {
            model.songs = [song("Alpha", status: .prod), song("Beta", status: .song)]
        }
        model.showAnalytics()
        XCTAssertEqual(model.analyticsSnapshot?.overview.finished, 0)

        model.mutateCatalog {
            var updated = model.songs
            updated[0].workflowStatus = .done
            model.songs = updated
        }

        XCTAssertEqual(model.analyticsSnapshot?.overview.finished, 1)
        XCTAssertEqual(model.analyticsSnapshot?.overview.totalSongs, 2)
    }

    func testCatalogUpdatesStayLazyOutsideAnalytics() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.mutateCatalog {
            model.songs = [song("Alpha")]
        }
        XCTAssertNil(model.analyticsSnapshot, "no snapshot before entering analytics")

        model.mutateCatalog {
            var updated = model.songs
            updated.append(song("Beta"))
            model.songs = updated
        }
        XCTAssertNil(model.analyticsSnapshot, "catalog churn outside analytics must stay lazy")

        model.showAnalytics()
        XCTAssertEqual(model.analyticsSnapshot?.overview.totalSongs, 2)

        model.viewMode = .board
        model.mutateCatalog {
            var updated = model.songs
            updated.append(song("Gamma"))
            model.songs = updated
        }
        XCTAssertEqual(
            model.analyticsSnapshot?.overview.totalSongs, 2,
            "leaving analytics must resume lazy snapshots until re-entry"
        )
    }

    func testSearchAndSelectionWhileAnalyticsOpenAvoidHistoryReads() {
        let store = HistoryCountingStore()
        let model = ArchiveBrowserViewModel(
            context: TestToolContext.make(),
            songMetadataStore: store
        )
        model.mutateCatalog {
            model.songs = [song("Neon Hook"), song("Ocean Drive")]
        }
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

        model.mutateCatalog {
            var updated = model.songs
            updated.append(song("Third Song"))
            model.songs = updated
        }
        XCTAssertEqual(store.historyReadCount, baselineReads + 1, "actual catalog updates must refresh")
        XCTAssertEqual(model.analyticsSnapshot?.overview.totalSongs, 3)
    }
}
