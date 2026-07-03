import XCTest

final class AppAppearanceControllerSourceTests: XCTestCase {
    func testAppAppearanceControllerSetsNSAppAppearance() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicHub/AppAppearanceController.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("NSApp.appearance"))
        XCTAssertTrue(source.contains("nsAppearanceName"))
    }
}
