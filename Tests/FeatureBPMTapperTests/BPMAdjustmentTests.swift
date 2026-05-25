import FeatureBPMTapper
import XCTest

final class BPMAdjustmentTests: XCTestCase {
    func testOriginalKeepsBPM() {
        XCTAssertEqual(BPMAdjustment.original.apply(to: 128.0), 128.0)
    }

    func testHalfTimeDividesBPM() {
        XCTAssertEqual(BPMAdjustment.halfTime.apply(to: 128.0), 64.0)
    }

    func testDoubleTimeMultipliesBPM() {
        XCTAssertEqual(BPMAdjustment.doubleTime.apply(to: 128.0), 256.0)
    }

    func testDisplayNamesMatchUISpec() {
        XCTAssertEqual(BPMAdjustment.original.displayName, "Original")
        XCTAssertEqual(BPMAdjustment.halfTime.displayName, "Half-Time")
        XCTAssertEqual(BPMAdjustment.doubleTime.displayName, "Double-Time")
    }
}
