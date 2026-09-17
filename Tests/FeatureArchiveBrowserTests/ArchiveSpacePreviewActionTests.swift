import XCTest
@testable import FeatureArchiveBrowser

final class ArchiveSpacePreviewActionTests: XCTestCase {
    func testSpaceWithNoSelectionTogglesLoadedPreview() {
        XCTAssertEqual(
            ArchiveSpacePreviewAction.resolve(selectedSongID: nil, loadedSongID: "a", hasLoadedPreview: true),
            .toggleLoaded
        )
    }

    func testSpaceWithNoSelectionAndNoPreviewDoesNothing() {
        XCTAssertEqual(
            ArchiveSpacePreviewAction.resolve(selectedSongID: nil, loadedSongID: nil, hasLoadedPreview: false),
            .none
        )
    }

    func testSpaceAuditionsWhenSelectionDiffersFromLoadedPreview() {
        // NMH-006: after Down to another song, Space must load that song — not toggle the stale player.
        XCTAssertEqual(
            ArchiveSpacePreviewAction.resolve(selectedSongID: "amber", loadedSongID: "neon", hasLoadedPreview: true),
            .auditionSelected
        )
    }

    func testSpaceTogglesWhenSelectionMatchesLoadedPreview() {
        XCTAssertEqual(
            ArchiveSpacePreviewAction.resolve(selectedSongID: "neon", loadedSongID: "neon", hasLoadedPreview: true),
            .toggleLoaded
        )
    }

    func testSpaceAuditionsWhenNothingLoadedYet() {
        XCTAssertEqual(
            ArchiveSpacePreviewAction.resolve(selectedSongID: "neon", loadedSongID: nil, hasLoadedPreview: false),
            .auditionSelected
        )
    }
}
