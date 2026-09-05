import XCTest
@testable import FeatureAudioRecorder

final class RecorderPermissionTests: XCTestCase {
    func testIncompatibleMacOSVersion() {
        let adapter = CoreAudioTapAdapter()
        let compatible = adapter.isCompatibleMacOS()
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 14 {
            XCTAssertFalse(compatible)
        } else {
            XCTAssertTrue(compatible)
        }
    }
}
