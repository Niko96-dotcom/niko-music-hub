import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

final class ArchiveBrowseProjectionTests: XCTestCase {
    func testProjectEmptySearchAppliesFilterAndSort() {
        let songA = Song(
            folderPath: URL(fileURLWithPath: "/tmp/alpha"),
            originalFolderName: "Alpha",
            displayTitle: "Alpha"
        )
        let songB = Song(
            folderPath: URL(fileURLWithPath: "/tmp/beta"),
            originalFolderName: "Beta",
            displayTitle: "Beta",
            scanWarnings: ["missing preview"]
        )
        var state = ArchiveBrowseState(
            songs: [songA, songB],
            showHiddenSongs: true,
            selectedShelf: .allSongs,
            selectedCollaboratorID: nil,
            searchQuery: "",
            browseFilter: [.hasWarnings],
            sortMode: .titleAZ,
            skippedScanEntries: []
        )

        let result = ArchiveBrowseProjection.project(state)
        XCTAssertEqual(result.filteredSongs.map(\.id), [songB.id])
        XCTAssertTrue(result.searchMatchSummaries.isEmpty)

        state.browseFilter = []
        state.searchQuery = "alp"
        let searched = ArchiveBrowseProjection.project(state)
        XCTAssertEqual(searched.filteredSongs.map(\.id), [songA.id])
        XCTAssertFalse(searched.searchMatchSummaries[songA.id, default: ""].isEmpty)
    }

    func testActiveSearchPreservesRelevanceOrderOverBrowseSort() {
        let older = Song(
            folderPath: URL(fileURLWithPath: "/tmp/older-match"),
            originalFolderName: "Older Match",
            displayTitle: "Older Neon Match"
        )
        let newer = Song(
            folderPath: URL(fileURLWithPath: "/tmp/newer-weak"),
            originalFolderName: "Newer Weak",
            displayTitle: "Zed Track",
            projectVersions: [
                ProjectVersion(
                    filePath: URL(fileURLWithPath: "/tmp/newer-weak/Newer.cpr"),
                    fileName: "Newer.cpr",
                    modifiedAt: Date(timeIntervalSince1970: 9_999_999)
                )
            ]
        )
        // "neon" should keep Older first by relevance even though Newer has a much newer CPR.
        let state = ArchiveBrowseState(
            songs: [newer, older],
            showHiddenSongs: true,
            selectedShelf: .allSongs,
            selectedCollaboratorID: nil,
            searchQuery: "neon",
            browseFilter: [],
            sortMode: .recentCPR,
            skippedScanEntries: []
        )
        let result = ArchiveBrowseProjection.project(state)
        XCTAssertEqual(result.filteredSongs.map(\.id), [older.id])
    }

    func testShelfHidesIgnoredSongsUnlessShowHiddenEnabled() {
        let visible = Song(
            folderPath: URL(fileURLWithPath: "/tmp/visible"),
            originalFolderName: "Visible",
            displayTitle: "Visible"
        )
        var hidden = Song(
            folderPath: URL(fileURLWithPath: "/tmp/hidden"),
            originalFolderName: "Hidden",
            displayTitle: "Hidden"
        )
        hidden.isIgnored = true
        let state = ArchiveBrowseState(
            songs: [visible, hidden],
            showHiddenSongs: false,
            selectedShelf: .allSongs,
            selectedCollaboratorID: nil,
            searchQuery: "",
            browseFilter: [],
            sortMode: .titleAZ,
            skippedScanEntries: []
        )

        XCTAssertEqual(ArchiveBrowseProjection.project(state).filteredSongs.map(\.id), [visible.id])

        var showingHidden = state
        showingHidden.showHiddenSongs = true
        XCTAssertEqual(
            ArchiveBrowseProjection.project(showingHidden).filteredSongs.map(\.id).sorted(),
            [visible.id, hidden.id].sorted()
        )
    }
}
