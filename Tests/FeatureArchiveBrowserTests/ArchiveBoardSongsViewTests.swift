import AppCore
import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

@MainActor
final class ArchiveBoardSongsViewTests: XCTestCase {
    func testCardComparisonTracksContentSelectionVaultAndActionOwner() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        let song = Song(folderPath: URL(fileURLWithPath: "/fixture-only/song"), originalFolderName: "Song", displayTitle: "Song")
        let original = ArchiveBoardSongCard(song: song, isSelected: false, vaultPresentation: nil, viewModel: model)
        XCTAssertEqual(original, ArchiveBoardSongCard(song: song, isSelected: false, vaultPresentation: nil, viewModel: model))
        XCTAssertNotEqual(original, ArchiveBoardSongCard(song: song, isSelected: true, vaultPresentation: nil, viewModel: model))
        var revised = song
        revised.virtualTitle = "Revised"
        revised.workflowStatus = .done
        revised.scanWarnings = ["Fixture warning"]
        XCTAssertNotEqual(original, ArchiveBoardSongCard(song: revised, isSelected: false, vaultPresentation: nil, viewModel: model))
        let vault = ProjectVaultCardPresentation(record: ProjectRecord(canonicalTitle: "Song", locations: []))
        XCTAssertNotEqual(original, ArchiveBoardSongCard(song: song, isSelected: false, vaultPresentation: vault, viewModel: model))
        let otherModel = ArchiveBrowserViewModel(context: TestToolContext.make())
        XCTAssertNotEqual(original, ArchiveBoardSongCard(song: song, isSelected: false, vaultPresentation: nil, viewModel: otherModel))
    }

    func testCollectionTracksOrderSelectionAndVaultChangesButIgnoresProgress() {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        let songs = ["A", "B"].map { Song(folderPath: URL(fileURLWithPath: "/fixture-only/\($0)"), originalFolderName: $0, displayTitle: $0) }
        let original = ArchiveBoardSongsView(songs: songs, selectedSongID: nil, vaultPresentations: [:], viewModel: model)
        model.statusMessage = "Scan progress"
        model.searchQuery = "Typing before debounce"
        XCTAssertEqual(original, ArchiveBoardSongsView(songs: songs, selectedSongID: nil, vaultPresentations: [:], viewModel: model))
        XCTAssertNotEqual(original, ArchiveBoardSongsView(songs: Array(songs.reversed()), selectedSongID: nil, vaultPresentations: [:], viewModel: model))
        XCTAssertNotEqual(original, ArchiveBoardSongsView(songs: songs, selectedSongID: songs[0].id, vaultPresentations: [:], viewModel: model))
        let vault = ProjectVaultCardPresentation(record: ProjectRecord(canonicalTitle: "A", locations: [], pinned: true))
        XCTAssertNotEqual(original, ArchiveBoardSongsView(songs: songs, selectedSongID: nil, vaultPresentations: [songs[0].id: vault], viewModel: model))
        var revised = songs
        revised[0].appNote = "Updated catalog metadata"
        XCTAssertNotEqual(original, ArchiveBoardSongsView(songs: revised, selectedSongID: nil, vaultPresentations: [:], viewModel: model))
    }
}
