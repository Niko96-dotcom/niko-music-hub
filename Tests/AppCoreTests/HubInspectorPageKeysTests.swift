@testable import AppCore
import XCTest

/// `HubInspectorPage` binds a page's Return and Esc keys (design contract §4).
@MainActor
final class HubInspectorPageKeysTests: XCTestCase {
    func testOnlyAnEnabledKeyIsInstalled() {
        XCTAssertEqual(HubPageKey.installed(HubPageKey("Convert") {}, onVisiblePage: true)?.title, "Convert")
        XCTAssertNil(HubPageKey.installed(HubPageKey("Stop After This File", isEnabled: false) {}, onVisiblePage: true))
        XCTAssertNil(HubPageKey.installed(nil, onVisiblePage: true))
    }

    /// The shell keeps a page you left mounted (opacity 0); its keys must not stay bound.
    func testAPageYouLeftInstallsNoKey() {
        XCTAssertNil(HubPageKey.installed(HubPageKey("Convert") {}, onVisiblePage: false))
        XCTAssertNil(HubPageKey.installed(HubPageKey("Stop") {}, onVisiblePage: false))
    }

    func testInstalledKeyRunsThePagesAction() {
        var ran = 0
        HubPageKey.installed(HubPageKey("Start Separation") { ran += 1 }, onVisiblePage: true)?.perform()
        XCTAssertEqual(ran, 1)
    }
}
