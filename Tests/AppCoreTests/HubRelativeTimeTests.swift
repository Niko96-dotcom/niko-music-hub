import AppCore
import XCTest

final class HubRelativeTimeTests: XCTestCase {
    func testJustCreatedItemsReadAsNowNotInZeroSeconds() {
        let reference = Date()
        for offset in [0.0, 0.2, -0.4] {
            let text = HubRelativeTime.string(for: reference.addingTimeInterval(offset), relativeTo: reference)
            XCTAssertFalse(text.contains("0"), "offset \(offset) rendered as \(text)")
        }
    }

    func testOlderItemsStillReadAsElapsedTime() {
        let reference = Date()
        let text = HubRelativeTime.string(for: reference.addingTimeInterval(-15 * 60), relativeTo: reference)
        XCTAssertTrue(text.contains("15"), text)
    }
}
