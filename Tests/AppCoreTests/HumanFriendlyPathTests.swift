import AppCore
import XCTest

final class HumanFriendlyPathTests: XCTestCase {
    func testMusicFolderUsesFriendlyLabel() {
        let home = "/Users/tester"
        let url = URL(fileURLWithPath: "\(home)/Music/Niko Music Hub/Inbox", isDirectory: true)
        XCTAssertEqual(
            HumanFriendlyPath.display(url, homeDirectory: home),
            "Music/Niko Music Hub/Inbox"
        )
    }

    func testArchiveRootSubtitleInMusic() {
        let home = "/Users/tester"
        let url = URL(fileURLWithPath: "\(home)/Music/00_Cubase Project", isDirectory: true)
        XCTAssertEqual(
            HumanFriendlyPath.archiveRootSubtitle(url, homeDirectory: home),
            "In Music"
        )
    }
}
