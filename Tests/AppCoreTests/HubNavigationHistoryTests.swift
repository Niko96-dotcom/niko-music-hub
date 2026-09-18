import AppCore
import XCTest

@MainActor
final class HubNavigationHistoryTests: XCTestCase {
    func testRecordCollapsesDuplicatesAndTruncatesForward() {
        let history = HubNavigationHistory()
        history.record(toolID: "a")
        history.record(toolID: "a")
        history.record(toolID: "b", route: "x")
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)

        XCTAssertEqual(history.goBack()?.toolID, "a")
        XCTAssertTrue(history.canGoForward)
        history.record(toolID: "c")
        XCTAssertEqual(history.entries.map(\.toolID), ["a", "c"])
        XCTAssertFalse(history.canGoForward)
    }

    func testRestoreSuppressesRecordingAndCallsRestorer() {
        let history = HubNavigationHistory()
        var restored: [String?] = []
        history.registerRestorer(for: "archive") { restored.append($0) }
        history.record(toolID: "archive", route: "board")
        history.record(toolID: "archive", route: "detail:1")
        let back = history.goBack()
        XCTAssertEqual(back?.route, "board")
        history.restore(back!)
        XCTAssertEqual(restored, ["board"])
        XCTAssertEqual(history.lastRoute(for: "archive"), "board")
        // A tool re-reporting the restored route must not add an entry.
        history.record(toolID: "archive", route: "board")
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertTrue(history.canGoForward)
    }

    func testToolSwitchUsesLastKnownRoute() {
        let history = HubNavigationHistory()
        history.noteRoute(toolID: "archive", route: "list:9")
        history.record(toolID: "bpm")
        history.record(toolID: "archive")
        XCTAssertEqual(history.current?.route, "list:9")
    }
}
