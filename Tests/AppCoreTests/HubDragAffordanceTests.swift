import XCTest

final class HubDragAffordanceTests: XCTestCase {
    func testGripHitPadAndHiddenFromAccessibility() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubDragAffordance.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains(".font(.system(size: 14"),
            "Grip glyph must be 14 pt."
        )
        XCTAssertTrue(
            source.contains(".frame(width: 28, height: 28)"),
            "Grip must have a 28 pt hit pad."
        )
        XCTAssertTrue(
            source.contains(".help(\"Drag to export\")"),
            "Grip must carry the Drag to export tooltip."
        )
        XCTAssertTrue(
            source.contains(".accessibilityHidden(true)"),
            "Grip must stay hidden from VoiceOver; Reveal is the alternative."
        )
        XCTAssertFalse(
            source.contains("size: 8"),
            "Grip must not use the 8 pt glyph."
        )
    }
}
