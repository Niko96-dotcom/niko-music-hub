import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

@MainActor
final class ArchiveBoardProjectionCacheTests: XCTestCase {
    func testSameFilteredSongsReuseExistingProjection() {
        let untriaged = song("/tmp/untriaged", title: "Untriaged", status: nil)
        let inProduction = song("/tmp/production", title: "Production", status: .prod)
        let cache = ArchiveBoardProjectionCache(songs: [untriaged, inProduction])
        let initialGeneration = cache.projectionGeneration
        let initialColumns = cache.columns

        // A card selection only changes `selectedSong`, not `filteredSongs`.
        XCTAssertFalse(cache.refresh(with: [untriaged, inProduction]))
        XCTAssertEqual(cache.projectionGeneration, initialGeneration)
        XCTAssertEqual(cache.columns, initialColumns)
    }

    func testChangedFilteredSongsRebuildsProjectionAndMovesCard() {
        let draft = song("/tmp/draft", title: "Draft", status: nil)
        let cache = ArchiveBoardProjectionCache(songs: [draft])
        let initialGeneration = cache.projectionGeneration

        var finished = draft
        finished.workflowStatus = .done

        XCTAssertTrue(cache.refresh(with: [finished]))
        XCTAssertEqual(cache.projectionGeneration, initialGeneration + 1)
        XCTAssertEqual(
            cache.columns.first(where: { $0.status == .done })?.songs.map(\.id),
            [finished.id]
        )
        XCTAssertTrue(
            cache.columns.first(where: { $0.status == nil })?.songs.isEmpty == true
        )
    }

    func testCardInteractionPolicyKeepsSelectionAndDetailActionsIndependent() {
        XCTAssertEqual(
            ArchiveBoardCardInteractionPolicy.action(for: .singleClick),
            .select
        )
        XCTAssertEqual(
            ArchiveBoardCardInteractionPolicy.action(for: .doubleClick),
            .openDetail
        )
        XCTAssertEqual(
            ArchiveBoardCardInteractionPolicy.action(for: .accessibilityDefault),
            .select
        )
        XCTAssertEqual(
            ArchiveBoardCardInteractionPolicy.action(for: .accessibilityOpenDetail),
            .openDetail
        )
    }

    private func song(
        _ path: String,
        title: String,
        status: ProjectWorkflowStatus?
    ) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: path, isDirectory: true),
            originalFolderName: title,
            displayTitle: title,
            workflowStatus: status
        )
    }
}
