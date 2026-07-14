import AppCore
import XCTest

final class QuickAccessCommandTests: XCTestCase {

    // MARK: - QuickAccessCommand enum

    func testOpenToolCarriesToolFeatureID() {
        let cmd = QuickAccessCommand.openTool("stem-separation")
        if case .openTool(let id) = cmd {
            XCTAssertEqual(id, ToolFeatureID("stem-separation"))
        } else {
            XCTFail("Expected .openTool case")
        }
    }

    func testOpenAppHasNoAssociatedValue() {
        // Verify it matches without crashing
        let cmd = QuickAccessCommand.openApp
        if case .openApp = cmd { } else { XCTFail("Expected .openApp case") }
    }

    func testRevealOutputInboxHasNoAssociatedValue() {
        let cmd = QuickAccessCommand.revealOutputInbox
        if case .revealOutputInbox = cmd { } else { XCTFail("Expected .revealOutputInbox case") }
    }

    func testCommandIsHashable() {
        let a = QuickAccessCommand.openTool("audio-recorder")
        let b = QuickAccessCommand.openTool("audio-recorder")
        let c = QuickAccessCommand.openTool("wav-converter")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - QuickAccessEntry allowlist shape

    func testAllowlistHasSixEntries() {
        XCTAssertEqual(QuickAccessEntry.allowlist.count, 6)
    }

    func testAllowlistOrderMatchesSpec() {
        let ids = QuickAccessEntry.allowlist.map(\.id)
        XCTAssertEqual(ids, [
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
        XCTAssertEqual(toolEntries.count, 5)
    }

    func testAllEntryIDsAreUnique() {
        let ids = QuickAccessEntry.allowlist.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Entry IDs must be unique for Identifiable conformance")
    }
}
