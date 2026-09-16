@testable import AppCore
import SwiftUI
import XCTest

/// NMH-134: Hub body type must use a scalable SwiftUI `Font.TextStyle`
/// (Accessibility → Display → Text Size) rather than a fixed `.system(size: 13)`.
///
/// Deviation from FIX-SPECS literal: on this SDK `String(describing: Font.body)`
/// is the opaque `Font(provider: SwiftUI.FontBox<SwiftUI.Font.TextStyleProvider>)`
/// — it contains neither `body` nor `size 13`. Assert the scalable provider
/// instead (fixed `.system(size:)` resolves to a different provider), keeping
/// the spec's negative `size 13` guard.
@MainActor
final class HubTypographyScalingTests: XCTestCase {
    func testBodyUsesTextStyleNotFixedSize() {
        let described = String(describing: HubDesignSystem.Typography.body())
        XCTAssertTrue(
            described.contains("TextStyleProvider"),
            "Typography.body() must use a TextStyle font, got: \(described)"
        )
        XCTAssertFalse(
            described.contains("size 13"),
            "Typography.body() must not be a fixed 13 pt font, got: \(described)"
        )
    }
}
