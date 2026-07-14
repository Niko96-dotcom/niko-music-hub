import CoreAudio
import XCTest
@testable import FeatureAudioRecorder

final class SystemAudioTapConfigurationTests: XCTestCase {
    func testGlobalTapCapturesAllProcessesByExcludingNone() {
        let description = SystemAudioTapConfiguration.makeGlobalTapDescription()

        XCTAssertEqual(description.name, SystemAudioTapConfiguration.tapName)
        XCTAssertTrue(description.isExclusive)
        XCTAssertTrue(description.isMixdown)
        XCTAssertFalse(description.isMono)
        XCTAssertTrue(description.isPrivate)
        XCTAssertEqual(description.muteBehavior, .unmuted)
        XCTAssertEqual(description.processes.count, 0)
    }

    func testAggregateTapAutoStarts() throws {
        let description = SystemAudioTapConfiguration.makeAggregateDeviceDescription(
            tapUID: "tap-uid",
            outputDeviceUID: "output-uid"
        )

        XCTAssertEqual(description[kAudioAggregateDeviceNameKey] as? String, SystemAudioTapConfiguration.aggregateDeviceName)
        XCTAssertEqual(description[kAudioAggregateDeviceMainSubDeviceKey] as? String, "output-uid")
        // The tap must auto-start with the aggregate device so it begins delivering PCM
        // immediately, independent of the output route (Bluetooth, USB, virtual, built-in).
        XCTAssertEqual(description[kAudioAggregateDeviceTapAutoStartKey] as? Bool, true)
        XCTAssertEqual(description[kAudioAggregateDeviceIsPrivateKey] as? Bool, true)
        XCTAssertEqual(description[kAudioAggregateDeviceIsStackedKey] as? Bool, false)

        let subDevices = try XCTUnwrap(description[kAudioAggregateDeviceSubDeviceListKey] as? [[String: String]])
        XCTAssertEqual(subDevices, [[kAudioSubDeviceUIDKey: "output-uid"]])
    }

    func testAggregateDescriptionContainsTapExactlyOnce() throws {
        let description = SystemAudioTapConfiguration.makeAggregateDeviceDescription(
            tapUID: "tap-uid",
            outputDeviceUID: "output-uid"
        )

        let taps = try XCTUnwrap(description[kAudioAggregateDeviceTapListKey] as? [[String: Any]])
        XCTAssertEqual(taps.count, 1, "The tap must be declared exactly once (single authoritative attachment path)")
        XCTAssertEqual(taps[0][kAudioSubTapUIDKey] as? String, "tap-uid")
        XCTAssertEqual(taps[0][kAudioSubTapDriftCompensationKey] as? Bool, true)
    }
}
