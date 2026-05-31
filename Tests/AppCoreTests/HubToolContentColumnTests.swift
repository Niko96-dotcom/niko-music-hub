import XCTest

final class HubToolContentColumnTests: XCTestCase {
    func testHubToolLayoutSourceDefinesContentColumnModifier() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubToolLayout.swift",
            encoding: .utf8
        )

        [
            "func hubToolContentColumn()",
            "HubToolLayout.maxContentWidth",
            ".frame(maxWidth: HubToolLayout.maxContentWidth",
            ".frame(maxWidth: .infinity",
            "hubToolContentPadding()",
        ].forEach {
            XCTAssertTrue(source.contains($0), "Missing hub tool column source: \($0)")
        }
    }
}
