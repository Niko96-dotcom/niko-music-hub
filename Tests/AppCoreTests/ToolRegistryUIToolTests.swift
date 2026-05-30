import AppCore
import XCTest

final class ToolRegistryUIToolTests: XCTestCase {
    func testInitialToolIDFromEnvironment() {
        XCTAssertEqual(
            ToolRegistry.initialToolID(from: ["NIKO_MUSIC_HUB_UI_TOOL": "bpm-tapper"])?.rawValue,
            "bpm-tapper"
        )
        XCTAssertNil(ToolRegistry.initialToolID(from: [:]))
        XCTAssertNil(ToolRegistry.initialToolID(from: ["NIKO_MUSIC_HUB_UI_TOOL": "  "]))
    }
}
