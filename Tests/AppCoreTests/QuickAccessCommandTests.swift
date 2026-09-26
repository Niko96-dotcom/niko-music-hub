import AppCore
import XCTest

final class QuickAccessCommandTests: XCTestCase {

    // MARK: - QuickAccessCommand enum

    func testCommandIsHashable() {
        let a = QuickAccessCommand.openTool("audio-recorder")
        let b = QuickAccessCommand.openTool("audio-recorder")
        let c = QuickAccessCommand.openTool("wav-converter")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - QuickAccessEntry allowlist shape

    func testAllowlistOrderMatchesSpec() {
        let ids = QuickAccessEntry.allowlist.map(\.id)
        XCTAssertEqual(ids, [
            "archive-browser",
            "audio-recorder",
            "wav-converter",
            "bpm-tapper",
            "downloader",
            "stem-separation",
            "output-inbox",
        ])
    }

    func testStemSeparationEntryMapsToOpenTool() {
        guard let entry = QuickAccessEntry.allowlist.first(where: { $0.id == "stem-separation" }) else {
            XCTFail("stem-separation entry missing from allowlist")
            return
        }
        XCTAssertEqual(entry.command, .openTool("stem-separation"))
    }

    func testOutputInboxEntryMapsToRevealOutputInbox() {
        guard let entry = QuickAccessEntry.allowlist.first(where: { $0.id == "output-inbox" }) else {
            XCTFail("output-inbox entry missing from allowlist")
            return
        }
        XCTAssertEqual(entry.command, .revealOutputInbox)
    }

    func testAllToolEntriesCarryOpenToolCommand() {
        let toolEntries = QuickAccessEntry.allowlist.filter {
            if case .openTool = $0.command { return true }
            return false
        }
        XCTAssertEqual(toolEntries.count, 6)
    }

    func testFocusArchiveSearchMapsFormerRestoreProjectCommand() {
        XCTAssertEqual(QuickAccessCommand.restoreProject, .focusArchiveSearch)
    }

}
