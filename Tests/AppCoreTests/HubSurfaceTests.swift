import AppCore
import SwiftUI
import XCTest

/// Covers the DEPTH-01/02/03 surface refactor: first-class Elevation/Highlight tokens and the
/// unified `HubSurface` primitive that every bounded surface (and the deprecated adapters)
/// now resolves through.
final class HubSurfaceTests: XCTestCase {

    // DEPTH-01: Elevation is a semantic, ordered scale (flat < low < medium < high).
    func testElevationTokensAreOrdered() {
        XCTAssertEqual(HubDesignSystem.Elevation.flat.radius, 0)
        XCTAssertLessThan(HubDesignSystem.Elevation.low.radius, HubDesignSystem.Elevation.medium.radius)
        XCTAssertLessThan(HubDesignSystem.Elevation.medium.radius, HubDesignSystem.Elevation.high.radius)
        XCTAssertEqual(HubDesignSystem.Elevation.flat.y, 0)
        XCTAssertLessThan(HubDesignSystem.Elevation.low.y, HubDesignSystem.Elevation.medium.y)
        XCTAssertLessThan(HubDesignSystem.Elevation.medium.y, HubDesignSystem.Elevation.high.y)
    }

    // DEPTH-02: Highlight (light-catching) tokens are exposed.
    func testHighlightTokensExposed() {
        _ = HubDesignSystem.Highlight.rim
        _ = HubDesignSystem.Highlight.rimStrong
        _ = HubDesignSystem.Highlight.sheen
        _ = HubDesignSystem.Highlight.underside
        _ = HubDesignSystem.Highlight.hairline
    }

    // DEPTH-03: surface levels resolve semantic corner radii from the Radius scale.
    func testSurfaceLevelCornerRadii() {
        XCTAssertEqual(HubSurfaceLevel.chrome.cornerRadius, 0)
        XCTAssertEqual(HubSurfaceLevel.panel.cornerRadius, HubDesignSystem.Radius.panel)
        XCTAssertEqual(HubSurfaceLevel.card.cornerRadius, HubDesignSystem.Radius.card)
        XCTAssertEqual(HubSurfaceLevel.raised.cornerRadius, HubDesignSystem.Radius.card)
        XCTAssertEqual(HubSurfaceLevel.field.cornerRadius, HubDesignSystem.Radius.row)
        XCTAssertEqual(HubSurfaceLevel.chip.cornerRadius, HubDesignSystem.Radius.chip)
    }

    // The primitive applies across every level × interactive state (compile/render smoke).
    @MainActor
    func testHubSurfaceAppliesToAllLevelsAndStates() {
        let levels: [HubSurfaceLevel] = [.chrome, .panel, .card, .raised, .field, .chip]
        for level in levels {
            for state in HubDesignSystem.ControlState.allCases {
                _ = Text("x").hubSurface(level, state: state)
            }
        }
    }

    // DEPTH-03: HubCard delegates to the single primitive; content stays opaque; chrome
    // Liquid Glass lives in HubMaterial (macOS 26), not on raised cards.
    func testCardDelegatesToSurfaceAndChromeIsGlassMaterial() throws {
        let cardSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubCard.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            cardSource.contains("hubSurface(.card"),
            "HubCard must delegate to the unified HubSurface primitive (DEPTH-03)."
        )
        XCTAssertTrue(cardSource.contains("interactive: interactive"))

        let surfaceSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubSurface.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            surfaceSource.contains("hubChromeMaterial()"),
            "HubSurface.chrome must resolve to the glass chrome material."
        )
        XCTAssertFalse(
            surfaceSource.contains(".glassEffect("),
            "HubSurface must not apply Liquid Glass to content; raised/card/field stay opaque."
        )
        XCTAssertFalse(
            surfaceSource.contains("level == .raised") && surfaceSource.contains(".glassEffect("),
            "HubSurface.swift must not pair .raised with glassEffect."
        )

        let materialSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubMaterial.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            materialSource.contains("#available(macOS 26.0") && materialSource.contains(".glassEffect("),
            "HubMaterial hosts one Liquid Glass sheet for chrome on macOS 26."
        )
        XCTAssertTrue(
            materialSource.contains("accessibilityReduceTransparency"),
            "Chrome glass must skip when Reduce Transparency is on."
        )
    }
}
