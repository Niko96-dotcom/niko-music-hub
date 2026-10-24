@testable import AppCore
import XCTest

/// `HubInspectorPage` binds a page's Return and Esc keys (design contract §4).
@MainActor
final class HubInspectorPageKeysTests: XCTestCase {
    func testOnlyAnEnabledKeyIsInstalled() {
        XCTAssertEqual(HubPageKey.installed(HubPageKey("Convert") {})?.title, "Convert")
        XCTAssertNil(HubPageKey.installed(HubPageKey("Stop After This File", isEnabled: false) {}))
        XCTAssertNil(HubPageKey.installed(nil))
    }

    func testInstalledKeyRunsThePagesAction() {
        var ran = 0
        HubPageKey.installed(HubPageKey("Start Separation") { ran += 1 })?.perform()
        XCTAssertEqual(ran, 1)
    }
}
