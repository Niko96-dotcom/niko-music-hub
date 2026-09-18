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
            materialSource.contains("material: .sidebar") && materialSource.contains("blending: .behindWindow"),
            "HubMaterial hosts one system .sidebar vibrancy sheet per chrome column (the Codex rail material)."
        )
        XCTAssertFalse(
            materialSource.contains(".glassEffect(.regular"),
            "Chrome rails are frosted sidebar vibrancy, never lens-like Liquid Glass (contract 1.1)."
        )
        XCTAssertTrue(
            materialSource.contains("accessibilityReduceTransparency"),
            "Chrome glass must skip when Reduce Transparency is on."
        )
    }

    // Contract 1.1 (2026-09-18, measured against Codex): chrome = system sidebar
    // vibrancy + one flat neutral veil; no gradient, rim or Liquid Glass.
    func testChromeMaterialIsSidebarVibrancyPlusFlatVeil() throws {
        let materialSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubMaterial.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            materialSource.contains("material: .sidebar"),
            "Chrome must use the system .sidebar material (what the Codex sidebar is built from)."
        )
        XCTAssertFalse(
            materialSource.contains("func hubTopSheen"),
            "Dead fake-glass hubTopSheen helper must stay deleted (zero call sites)."
        )
        XCTAssertFalse(
            materialSource.contains("LinearGradient"),
            "No depth gradient over the chrome material (contract 1.1): one flat veil only."
        )
        XCTAssertTrue(
            materialSource.contains("Color.white.opacity(0.30)") && materialSource.contains("Color.white.opacity(0.05)"),
            "Rail veil is pinned to the measured Codex tones (light 205→220, dark 41→51)."
        )
        XCTAssertTrue(
            materialSource.contains("extendAboveBy"),
            "Nested rails must be able to extend through the shell title row."
        )

        let systemSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubDesignSystem.swift",
            encoding: .utf8
        )
        XCTAssertFalse(systemSource.contains("var glassInnerHighlight"))
        XCTAssertFalse(systemSource.contains("var glassStroke"))
        XCTAssertTrue(systemSource.contains("selectedRowFill"))
        // Opaque standard window; sidebar vibrancy needs no transparent window.
        let chromeSource = try String(
            contentsOfFile: "Sources/NikoMusicHub/AppShell/HubWindowChromeConfigurator.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            chromeSource.contains("window.isOpaque = true"),
            "Main window stays opaque (no LIQUID-KEY shine-through)."
        )
        XCTAssertFalse(
            chromeSource.contains("window.backgroundColor = .clear"),
            "Main window background must not be cleared (nothing refracts the desktop any more)."
        )
        XCTAssertTrue(
            chromeSource.contains("HubShellLayout.titleBarAxisY") && chromeSource.contains("bar.isFlipped"),
            "Traffic lights centre on the title row via their titlebar view's own coordinates."
        )
        XCTAssertTrue(
            chromeSource.contains("window.makeFirstResponder(nil)"),
            "Launch must not leave keyboard focus (and our focus ring) on the sidebar toggle."
        )
        // Selection pill: translucent neutral step that survives any rail tone
        // (Codex measured: light −10 on 220, dark +15 on 51).
        XCTAssertTrue(
            systemSource.contains("light: Color.black.opacity(0.055)") && systemSource.contains("dark:  Color.white.opacity(0.09)"),
            "Palette.selection is a translucent neutral pill calibrated to the Codex sidebar step."
        )
        // Dark neutral scale = Codex content column (warm neutral 45/45/43), not inky blue-black.
        XCTAssertTrue(
            systemSource.contains("red: 45/255,  green: 45/255,  blue: 43/255"),
            "Dark canvas is pinned to the measured Codex content tone."
        )
    }
}
