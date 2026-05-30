import AppCore
import XCTest

final class MusicHubRuntimeEnvironmentTests: XCTestCase {
    func testParsesHarnessFlags() {
        let runtime = MusicHubRuntimeEnvironment(environment: [
            MusicHubRuntimeEnvironment.dryRunOpenKey: "1",
            MusicHubRuntimeEnvironment.fixtureRootKey: "/tmp/nmh-fixture",
            MusicHubRuntimeEnvironment.settingsSuiteKey: "nmh-test",
            MusicHubRuntimeEnvironment.showDevToolKey: "1",
            MusicHubRuntimeEnvironment.disableArchiveWatcherKey: "1",
            MusicHubRuntimeEnvironment.e2eSmokeKey: "1",
        ])

        XCTAssertTrue(runtime.dryRunOpen)
        XCTAssertEqual(runtime.fixtureRootURL?.path, "/tmp/nmh-fixture")
        XCTAssertTrue(runtime.usesFixtureRoot)
        XCTAssertEqual(runtime.settingsSuiteName, "nmh-test")
        XCTAssertTrue(runtime.usesIsolatedSettingsSuite)
        XCTAssertTrue(runtime.showsDevTool)
        XCTAssertTrue(runtime.disableArchiveWatcher)
        XCTAssertTrue(runtime.e2eSmoke)
    }

    func testEmptyFixtureRootIsIgnored() {
        let runtime = MusicHubRuntimeEnvironment(environment: [
            MusicHubRuntimeEnvironment.fixtureRootKey: "  ",
        ])
        XCTAssertNil(runtime.fixtureRootURL)
        XCTAssertFalse(runtime.usesFixtureRoot)
    }
}
