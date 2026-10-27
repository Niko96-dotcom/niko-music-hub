import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

/// The page owner on its own: a root change keeps the layout the person chose but
/// forgets the song and the compact list's detail, so the next single click selects
/// instead of opening a detail for a song that is gone (seen in the 2026-10-26 acceptance run).
@MainActor
final class ArchivePageModelTests: XCTestCase {
    private func makeSong(_ name: String) -> Song {
        let folder = URL(fileURLWithPath: "/tmp/page-model/\(name)", isDirectory: true)
        let version = ProjectVersion(
            filePath: folder.appendingPathComponent("\(name).cpr"), fileName: "\(name).cpr",
            modifiedAt: Date(timeIntervalSince1970: 1_000))
        return Song(folderPath: folder, originalFolderName: name, displayTitle: name,
                    projectVersions: [version], previewCandidates: [], mainPreviewCandidateID: nil,
                    latestCPR: version)
    }

    func testARootChangeKeepsTheListLayoutButLeavesTheCompactDetail() {
        let page = ArchivePageModel(selectionDidChange: { _ in })
        page.setBrowseLayout(list: true)
        page.select(makeSong("Neon Hook"))
        page.openDetail()
        page.songDetailsExpanded = true
        XCTAssertTrue(page.listShowsDetail)

        page.clearForRootChange()

        XCTAssertEqual(page.viewMode, .list, "the layout is the person's choice and survives a root change")
        XCTAssertNil(page.selectedSong)
        XCTAssertFalse(page.listShowsDetail, "the detail belonged to a song of the old root")
        XCTAssertFalse(page.songDetailsExpanded)

        page.select(makeSong("Amber Moth"))
        XCTAssertFalse(page.listShowsDetail, "the first click after a root change selects; it does not open the detail")
    }

    func testARootChangeOnTheBoardDetailShowsTheBoardAgain() {
        let page = ArchivePageModel(selectionDidChange: { _ in })
        page.select(makeSong("Neon Hook"))
        page.openDetail()
        XCTAssertEqual(page.viewMode, .boardDetail)

        page.clearForRootChange()

        XCTAssertNil(page.selectedSong)
        XCTAssertTrue(page.showsBoardPage, "a detail page whose song disappeared shows the board under it")
    }
}
