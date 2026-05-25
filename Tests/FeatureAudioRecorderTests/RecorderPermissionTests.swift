import XCTest
@testable import FeatureAudioRecorder

final class RecorderPermissionTests: XCTestCase {
    func testPermissionStateIsKnownValue() async {
        let adapter = CoreAudioTapAdapter()
        let state = await adapter.checkPermission()
        switch state {
        case .authorized, .denied, .restricted, .notDetermined:
            break
        }
    }

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
