import AppCore
import XCTest

final class AppBuildIdentityTests: XCTestCase {
    func testPrefersExactBuildIDForCompactLabel() {
        let identity = AppBuildIdentity(infoDictionary: [
            "CFBundleShortVersionString": "1.4.1",
            "NMHBuildID": "1.4.1+abcdef123456",
            "NMHSourceCommit": "abcdef1234567890",
        ])

        XCTAssertEqual(identity.compactLabel, "v1.4.1+abcdef123456")
        XCTAssertEqual(identity.shortSourceCommit, "abcdef123456")
    }

    func testFallsBackToMarketingVersionForUnstampedBundles() {
        let identity = AppBuildIdentity(infoDictionary: [
            "CFBundleShortVersionString": "1.4.1",
        ])

        XCTAssertEqual(identity.compactLabel, "v1.4.1")
        XCTAssertNil(identity.buildID)
        XCTAssertNil(identity.shortSourceCommit)
    }
}
