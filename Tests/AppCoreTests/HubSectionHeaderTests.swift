import XCTest

final class HubSectionHeaderTests: XCTestCase {
    private func headerSource() throws -> String {
        try String(
            contentsOfFile: "Sources/AppCore/Components/HubSectionHeader.swift",
            encoding: .utf8
        )
    }

    func testHeaderActionUsesIconButtonSize() throws {
        let source = try headerSource()
        XCTAssertTrue(
            source.contains("HubDesignSystem.Size.iconButtonSize"),
            "Section header action must size to HubDesignSystem.Size.iconButtonSize"
        )
        XCTAssertFalse(
            source.contains(".frame(width: 20, height: 20)"),
            "Section header action must not use the 20 pt frame"
        )
    }

    func testHeaderTraitIsOnTitleNotStack() throws {
        let source = try headerSource()
        let trait = ".accessibilityAddTraits(.isHeader)"
        let occurrences = source.components(separatedBy: trait).count - 1
        XCTAssertEqual(occurrences, 1, "isHeader trait must appear exactly once (on the title)")

        guard let titleRange = source.range(of: "Text(title)"),
              let traitRange = source.range(of: trait)
        else {
            return XCTFail("Missing Text(title) or isHeader trait in HubSectionHeader.swift")
        }
        XCTAssertTrue(
            titleRange.lowerBound < traitRange.lowerBound,
            "isHeader trait must follow the title Text(title) block"
        )
        XCTAssertFalse(
            source.contains(".padding(.bottom, 4)\n        .accessibilityAddTraits(.isHeader)"),
            "isHeader trait must not be applied to the outer HStack"
        )
    }
}
