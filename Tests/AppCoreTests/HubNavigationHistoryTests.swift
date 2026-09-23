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

    func testRestoreFallbackReReportKeepsLastRouteInSyncWithoutAddingEntries() {
        // Behavioral contract the archive relies on: restore pre-writes the
        // requested route, then the restorer synchronously re-reports the
        // actual route it landed on (the archive does this via its Combine
        // route publication, which calls record during the restore window).
        // record during restore updates lastRoutes without appending.
        let history = HubNavigationHistory()
        history.registerRestorer(for: "archive") { route in
            if route == "detail:missing" {
                history.record(toolID: "archive", route: "board")
            } else if route == "list:missing" {
                history.record(toolID: "archive", route: "list")
            }
        }
        history.record(toolID: "archive", route: "board")
        history.record(toolID: "archive", route: "detail:missing")
        XCTAssertEqual(history.entries.count, 2)

        history.restore(HubNavigationEntry(toolID: "archive", route: "detail:missing"))

        XCTAssertEqual(history.lastRoute(for: "archive"), "board")
        XCTAssertEqual(history.entries.count, 2, "restore must not append entries")
        XCTAssertEqual(history.entries.map(\.route), ["board", "detail:missing"])
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testToolSwitchAfterFallbackRestoreUsesActualRoute() {
        let history = HubNavigationHistory()
        history.registerRestorer(for: "archive") { route in
            if route == "detail:missing" {
                history.record(toolID: "archive", route: "board")
            }
        }
        history.record(toolID: "archive", route: "board")
        history.record(toolID: "archive", route: "detail:missing")
        history.restore(HubNavigationEntry(toolID: "archive", route: "detail:missing"))
        XCTAssertEqual(history.lastRoute(for: "archive"), "board")

        history.record(toolID: "bpm")
        history.record(toolID: "archive")

        XCTAssertEqual(history.current?.toolID, "archive")
        XCTAssertEqual(history.current?.route, "board", "tool switch must reuse the actual restored route, not the stale detail")
    }

    func testRestoredListFallbackUsesActualRoute() {
        let history = HubNavigationHistory()
        history.registerRestorer(for: "archive") { route in
            if route == "list:missing" {
                history.record(toolID: "archive", route: "list")
            }
        }
        history.record(toolID: "archive", route: "list:9")
        history.restore(HubNavigationEntry(toolID: "archive", route: "list:missing"))

        XCTAssertEqual(history.lastRoute(for: "archive"), "list")
        XCTAssertEqual(history.entries.count, 1, "restore must not append entries")
    }
}
