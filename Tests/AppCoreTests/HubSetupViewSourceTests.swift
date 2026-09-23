import XCTest

final class HubSetupViewSourceTests: XCTestCase {
    func testHubSetupViewUsesOneClickCopyAndWarmProgress() throws {
        let source = try SourceTestSupport.read("Sources/NikoMusicHub/Onboarding/HubSetupView.swift")

        XCTAssertTrue(source.contains("Install All"))
        XCTAssertTrue(source.contains("hub_setup_sheet"))
        XCTAssertTrue(source.contains(".tint(HubDesignSystem.Colors.indicator)"))

        XCTAssertFalse(source.contains("Welcome to"))
        XCTAssertFalse(source.contains("brew"))
        XCTAssertFalse(source.contains("Terminal"))
        XCTAssertFalse(source.contains(".bordered"))
        XCTAssertFalse(source.contains("Capsule("))
    }

    func testHelperToolsHealthStripPointsToSetupSheet() throws {
        let source = try SourceTestSupport.read("Sources/NikoMusicHub/AppShell/HelperToolsHealthStrip.swift")

        XCTAssertFalse(source.contains("Homebrew"))
    }
}
