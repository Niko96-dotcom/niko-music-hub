@testable import AppCore
import XCTest

final class HubStepSliderTests: XCTestCase {
    func testEmptyStepsYieldNoValueInsteadOfTrapping() {
        XCTAssertNil(HubStepSlider<Int>.step(at: 0, in: []))
        XCTAssertNil(HubStepSlider<Int>.step(at: 1, in: []))
    }

    func testPositionIsClampedToSteps() {
        XCTAssertEqual(HubStepSlider<Int>.step(at: 1, in: [5]), 5)
        XCTAssertEqual(HubStepSlider<Int>.step(at: -3, in: [5, 10, 0]), 5)
        XCTAssertEqual(HubStepSlider<Int>.step(at: 1.4, in: [5, 10, 0]), 10)
        XCTAssertEqual(HubStepSlider<Int>.step(at: 9, in: [5, 10, 0]), 0)
    }
}
