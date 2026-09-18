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

    // Contract 1.1 (2026-09-18): the macOS 26 chrome glass path is system-owned.
    func testChromeGlassPathIsSystemOwned() throws {
        let materialSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubMaterial.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            materialSource.contains(".glassEffect(.regular, in: .rect)"),
            "Chrome must use the regular Liquid Glass variant in a rect sheet."
        )
        XCTAssertFalse(
            materialSource.contains("func hubTopSheen"),
            "Dead fake-glass hubTopSheen helper must stay deleted (zero call sites)."
        )
        if let glassRange = materialSource.range(of: "System glass path"),
           let fallbackRange = materialSource.range(of: "Opaque when inactive")
        {
            let glassSection = String(materialSource[glassRange.lowerBound..<fallbackRange.lowerBound])
            XCTAssertFalse(
                glassSection.contains("LinearGradient"),
                "No custom gradient over native glassEffect (contract 1.1)."
            )
        } else {
            XCTFail("HubMaterial must keep the glass/fallback section markers for 1.1.")
        }

        let systemSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubDesignSystem.swift",
            encoding: .utf8
        )
        XCTAssertFalse(systemSource.contains("var glassInnerHighlight"))
        XCTAssertFalse(systemSource.contains("var glassStroke"))
        XCTAssertTrue(systemSource.contains("selectedRowFill"))
        // LIQUID-KEY: transparent window for desktop shine-through (guarded sets).
        let chromeSource = try String(
            contentsOfFile: "Sources/NikoMusicHub/AppShell/HubWindowChromeConfigurator.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            chromeSource.contains("window.isOpaque = false"),
            "Main window must be non-opaque so chrome glass refracts the desktop."
        )
        XCTAssertTrue(
            chromeSource.contains("window.backgroundColor = .clear"),
            "Main window background must be clear so chrome glass refracts the desktop."
        )
        // LIQUID-KEY: glass only while key; inactive chrome is opaque, never dimmed glass.
        XCTAssertTrue(
            materialSource.contains("isWindowActive"),
            "Chrome backdrop must gate glass on key-window state."
        )
        XCTAssertFalse(
            materialSource.contains(".opacity(isWindowActive ? 1 : 0.55)"),
            "Inactive chrome must be opaque, not dimmed glass (LIQUID-KEY)."
        )
        XCTAssertTrue(
            systemSource.contains("92/255"),
            "Dark Palette.selection is pinned to the measured live-glass floor (rgb 92,92,96): "
                + "the active glass rail renders ~63 over a dark desktop, the old 64-fill was invisible."
        )
    }
}
