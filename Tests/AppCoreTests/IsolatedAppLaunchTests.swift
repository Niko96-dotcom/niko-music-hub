import AppCore
import XCTest

final class IsolatedAppLaunchTests: XCTestCase {
    private let canonical = "com.niko96.NikoMusicHub"

    func testProductionLaunchWithoutSuiteIsUnchanged() throws {
        XCTAssertNil(try IsolatedAppLaunch.settingsSuite(requested: nil, declared: nil, bundleID: canonical, canonicalID: nil))
    }

    func testProductionBundleCannotUseAnIsolatedSuite() {
        XCTAssertThrowsError(try IsolatedAppLaunch.settingsSuite(requested: "Fixture", declared: nil, bundleID: canonical, canonicalID: nil))
    }

    func testFixtureBundleKeepsSuiteOnFinderRelaunch() throws {
        let bundleID = IsolatedAppLaunch.bundleIdentifier(canonical: canonical, suite: "Fixture")
        XCTAssertEqual(bundleID, canonical + ".isolated.2ab25f10948b26d7")
        XCTAssertNotEqual(bundleID, IsolatedAppLaunch.bundleIdentifier(canonical: canonical, suite: "Other"))
        for requested in [nil, "Fixture"] {
            XCTAssertEqual(try IsolatedAppLaunch.settingsSuite(requested: requested, declared: "Fixture", bundleID: bundleID, canonicalID: canonical), "Fixture")
        }
        XCTAssertThrowsError(try IsolatedAppLaunch.settingsSuite(requested: "Other", declared: "Fixture", bundleID: bundleID, canonicalID: canonical))
        XCTAssertThrowsError(try IsolatedAppLaunch.settingsSuite(requested: nil, declared: "Fixture", bundleID: canonical, canonicalID: canonical))
        XCTAssertThrowsError(try IsolatedAppLaunch.settingsSuite(requested: nil, declared: canonical, bundleID: IsolatedAppLaunch.bundleIdentifier(canonical: canonical, suite: canonical), canonicalID: canonical))
    }
}
