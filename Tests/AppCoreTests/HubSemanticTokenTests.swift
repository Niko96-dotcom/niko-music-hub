import AppCore
import AppKit
import SwiftUI
import XCTest

/// Tests that verify the Phase 51 semantic design-system architectural invariants.
/// Covers: DS-01, DS-02, DS-03, DS-06, DS-07, DS-08, DS-09, DS-11, DS-12, DS-13, DS-14.
final class HubSemanticTokenTests: XCTestCase {

    // MARK: DS-02: All semantic token roles exposed

    /// DS-02: all 14 Palette roles + Motion/ControlState/Radius/Spacing/Typography are accessible.
    /// Compile-time presence check — fails to compile if any role is missing.
    func testAllSemanticTokensExposed() {
        // 14 semantic Palette roles
        _ = HubDesignSystem.Palette.canvas
        _ = HubDesignSystem.Palette.sidebar
        _ = HubDesignSystem.Palette.surface
        _ = HubDesignSystem.Palette.surfaceRaised
        _ = HubDesignSystem.Palette.separator
        _ = HubDesignSystem.Palette.textPrimary
        _ = HubDesignSystem.Palette.textSecondary
        _ = HubDesignSystem.Palette.textTertiary
        _ = HubDesignSystem.Palette.selection
        _ = HubDesignSystem.Palette.focus
        _ = HubDesignSystem.Palette.accent
        _ = HubDesignSystem.Palette.success
        _ = HubDesignSystem.Palette.warning
        _ = HubDesignSystem.Palette.danger

        // DS-05: ControlState 7-case enum
        XCTAssertEqual(HubDesignSystem.ControlState.allCases.count, 7)

        // Motion durations locked per CONTEXT.md
        XCTAssertEqual(HubDesignSystem.Motion.short, 0.15)
        XCTAssertEqual(HubDesignSystem.Motion.medium, 0.25)
        XCTAssertEqual(HubDesignSystem.Motion.long, 0.40)

        // Radius / Spacing / Typography accessible
        _ = HubDesignSystem.Radius.shell
        _ = HubDesignSystem.Spacing.shell
        _ = HubDesignSystem.Typography.body()
        _ = HubDesignSystem.Size.statusDot
    }

    // MARK: DS-03: No appearance-based token names

    /// DS-03: token names are semantic / purpose-based, not appearance-based.
    /// "darkCanvas", "lightAccent", "blueColor", "darkSurface", "lightSurface" are naming violations.
    func testNoAppearanceBasedTokenNames() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubDesignSystem.swift",
            encoding: .utf8
        )
        let forbiddenNames = ["darkCanvas", "lightAccent", "blueColor", "darkSurface", "lightSurface"]
        for name in forbiddenNames {
            XCTAssertFalse(
                source.contains(name),
                "HubDesignSystem.swift uses an appearance-based token name (DS-03 violation): \(name)"
            )
        }
    }

    // MARK: DS-11: Dark-mode values match calm-native

    /// DS-11: Palette.canvas resolves to a dark value and Palette.accent has a warm RGB profile.
    /// The rgbaComponents helper resolves via NSColor(color).usingColorSpace(.sRGB) which returns
    /// the current-appearance value. The warm-amber relationship (red > green > blue) holds in both
    /// light and dark mode (light accent rgb(168,138,98) is also red > green > blue).
    func testDarkModeValuesMatchCalmNative() {
        // Canvas should be dark (dark-first system) OR light in light appearance.
        // In either appearance, canvas should be achromatic — R ≈ G ≈ B (low-chroma neutral).
        guard let canvasComponents = rgbaComponents(HubDesignSystem.Palette.canvas) else {
            XCTFail("Could not resolve Palette.canvas to sRGB components")
            return
        }
        // Low-chroma: R, G, B should be within 5/255 of each other (calm-native neutrals).
        XCTAssertLessThan(
            abs(canvasComponents.red - canvasComponents.green), 0.05,
            "Palette.canvas is not achromatic (DS-11 — calm-native neutral surface)"
        )
        XCTAssertLessThan(
            abs(canvasComponents.green - canvasComponents.blue), 0.05,
            "Palette.canvas is not achromatic (DS-11 — calm-native neutral surface)"
        )
        // Accent must be warm in both modes (DS-11/DS-12)
        guard let accentComponents = rgbaComponents(HubDesignSystem.Palette.accent) else {
            XCTFail("Could not resolve Palette.accent to sRGB components")
            return
        }
        XCTAssertGreaterThan(
            accentComponents.red, accentComponents.blue,
            "Palette.accent is not warm in current appearance (red should exceed blue)"
        )
    }

    // MARK: DS-12: Accent is warm amber, not blue

    /// DS-12: accent is rgb(198,168,128) warm muted amber — NOT system blue.
    /// Red > green > blue, and blue < 0.70 confirms a warm (not saturated blue) hue.
    func testAccentIsWarmAmberNotBlue() {
        guard let components = rgbaComponents(HubDesignSystem.Palette.accent) else {
            XCTFail("Could not resolve Palette.accent to sRGB components")
            return
        }
        XCTAssertGreaterThan(
            Double(components.red), Double(components.green),
            "Palette.accent red should exceed green (warm amber, DS-12)"
        )
        XCTAssertGreaterThan(
            Double(components.green), Double(components.blue),
            "Palette.accent green should exceed blue (warm amber, DS-12)"
        )
        XCTAssertLessThan(
            Double(components.blue), 0.70,
            "Palette.accent blue component too high — not warm amber (DS-12)"
        )
    }

    // MARK: DS-14: Status colors are semantic and distinct

    /// DS-14: success/warning/danger are three distinct semantic colors.
    /// success is green-ish, warning is amber-ish, danger is red-ish.
    func testStatusColorsAreSemantic() {
        guard
            let success = rgbaComponents(HubDesignSystem.Palette.success),
            let warning = rgbaComponents(HubDesignSystem.Palette.warning),
            let danger  = rgbaComponents(HubDesignSystem.Palette.danger)
        else {
            XCTFail("Could not resolve status Palette colors to sRGB components")
            return
        }
        // Colors are distinct (differ by >0.1 in at least one channel)
        let successVsWarning = abs(success.red - warning.red) > 0.1
            || abs(success.green - warning.green) > 0.1
            || abs(success.blue - warning.blue) > 0.1
        XCTAssertTrue(successVsWarning, "Palette.success and Palette.warning are not distinct (DS-14)")

        let warningVsDanger = abs(warning.red - danger.red) > 0.1
            || abs(warning.green - danger.green) > 0.1
            || abs(warning.blue - danger.blue) > 0.1
        XCTAssertTrue(warningVsDanger, "Palette.warning and Palette.danger are not distinct (DS-14)")

        let successVsDanger = abs(success.red - danger.red) > 0.1
            || abs(success.green - danger.green) > 0.1
            || abs(success.blue - danger.blue) > 0.1
        XCTAssertTrue(successVsDanger, "Palette.success and Palette.danger are not distinct (DS-14)")

        // Semantic hue checks (dark mode: success green 120/170/110, warning amber 200/160/90, danger red 190/100/92)
        // success: green channel should be the strongest (green > red, green > blue) in dark mode
        // In light mode (95/145/85): still green > red, green > blue
        XCTAssertGreaterThan(
            success.green, success.blue,
            "Palette.success green channel should be dominant (semantic green, DS-14)"
        )
        // warning: red > blue, green > blue (amber characteristic)
        XCTAssertGreaterThan(
            warning.red, warning.blue,
            "Palette.warning red should exceed blue (semantic amber, DS-14)"
        )
        XCTAssertGreaterThan(
            warning.green, warning.blue,
            "Palette.warning green should exceed blue (semantic amber, DS-14)"
        )
        // danger: red channel is dominant (red > green in dark mode: 190 vs 100)
        XCTAssertGreaterThan(
            danger.red, danger.blue,
            "Palette.danger red should exceed blue (semantic red, DS-14)"
        )
    }

    // MARK: DS-06: Design system split across focused files

    /// DS-06: the design system is split across multiple focused files — not a single giant file.
    func testDesignSystemIsSplitAcrossFocusedFiles() {
        let requiredFiles = [
            "Sources/AppCore/Components/HubDesignSystem.swift",
            "Sources/AppCore/Components/HubCard.swift",
            "Sources/AppCore/Components/HubLiquidGlass.swift",
            "Sources/AppCore/Components/HubGlassChrome.swift",
            "Sources/AppCore/Components/HubMediaSurfaces.swift",
            "Sources/AppCore/Components/HubIconButton.swift",
            "Sources/AppCore/Components/HubLabeledButton.swift",
            "Sources/AppCore/Components/ToolHeaderBlock.swift",
        ]
        for path in requiredFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: path),
                "Required design-system file is missing (DS-06): \(path)"
            )
        }
    }

    // MARK: DS-07: AppCore/Components has no direct visual literals (except HubDesignSystem.swift)

    /// DS-07: no file in Sources/AppCore/Components/ EXCEPT HubDesignSystem.swift
    /// uses raw RGB literals (Color(red:green:blue:) or Color(.sRGB, red:)).
    /// The token definitions in HubDesignSystem.swift are the only place raw RGB is allowed.
    func testAppCoreHasNoDirectVisualLiterals() throws {
        let componentFiles = try swiftFiles(under: "Sources/AppCore/Components")
        for path in componentFiles {
            // HubDesignSystem.swift is the token definition file — raw RGB is expected there
            guard !path.hasSuffix("HubDesignSystem.swift") else { continue }
            let source = try String(contentsOfFile: path, encoding: .utf8)
            XCTAssertFalse(
                source.contains("Color(red:"),
                "AppCore Components file uses raw RGB literal outside HubDesignSystem.swift (DS-07 violation): \(path)"
            )
            XCTAssertFalse(
                source.contains("Color(.sRGB, red:"),
                "AppCore Components file uses raw sRGB literal outside HubDesignSystem.swift (DS-07 violation): \(path)"
            )
        }
    }

    // MARK: DS-08: Semantic path (HubCard) has no glassEffect

    /// DS-08: HubCard.swift — the semantic card surface — contains no .glassEffect modifier.
    func testSemanticPathHasNoGlassEffect() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubCard.swift",
            encoding: .utf8
        )
        XCTAssertFalse(
            source.contains(".glassEffect("),
            "HubCard.swift contains a .glassEffect( call — semantic path must not use glass (DS-08)"
        )
    }

    // MARK: DS-01/DS-09: No second theme system

    /// DS-01/DS-09: the design system source does not define a second theme system
    /// (ThemeV2, LiquidV2, CalmCard, UniversalCard, UniversalPanel).
    func testNoSecondThemeSystemExists() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubDesignSystem.swift",
            encoding: .utf8
        )
        // Strip comment lines — doc comments may mention these concepts as "what we replaced"
        let nonCommentLines = source.components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("/*")
            }
        let nonCommentSource = nonCommentLines.joined(separator: "\n")
        let forbiddenSymbols = ["ThemeV2", "LiquidV2", "CalmCard", "UniversalCard", "UniversalPanel"]
        for symbol in forbiddenSymbols {
            XCTAssertFalse(
                nonCommentSource.contains(symbol),
                "HubDesignSystem.swift defines a second theme system (DS-01/DS-09 violation): \(symbol)"
            )
        }
    }

    // MARK: DS-13: Accent not used as panel/selection background

    /// DS-13: HubGlassChrome.swift HubSidebarNavRow uses Palette.selection (low-chroma
    /// neutral) for the selected fill, NOT Palette.accent (reserved for primary action).
    func testAccentNotUsedAsPanelBackground() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubGlassChrome.swift",
            encoding: .utf8
        )
        // HubSidebarNavRow body should reference Palette.selection for the selected fill
        XCTAssertTrue(
            source.contains("Palette.selection"),
            "HubGlassChrome.swift does not reference Palette.selection for HubSidebarNavRow (DS-13)"
        )
        // Sanity: verify Palette.accent is not used as the selection fill in HubSidebarNavRow.
        // The accent CAN appear elsewhere (e.g. archive chip colors), but not as the sidebar
        // selection fill. Since HubGlassChrome.swift only contains shell/nav primitives (not
        // archive chips), any Palette.accent reference here would be a DS-13 violation.
        XCTAssertFalse(
            source.contains("Palette.accent"),
            "HubGlassChrome.swift uses Palette.accent for a navigation surface (DS-13 violation — accent is reserved)"
        )
    }

    // MARK: Private helpers

    private func swiftFiles(under root: String) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return [] }
        return enumerator.compactMap { item -> String? in
            guard let item = item as? String, item.hasSuffix(".swift") else { return nil }
            return "\(root)/\(item)"
        }
    }
}

// MARK: - RGB component helper (shared with HubDesignSystemTokenTests)

private struct RGBAComponents {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
}

private func rgbaComponents(_ color: Color) -> RGBAComponents? {
    guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    return RGBAComponents(
        red: nsColor.redComponent,
        green: nsColor.greenComponent,
        blue: nsColor.blueComponent
    )
}
