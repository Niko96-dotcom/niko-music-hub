@testable import AppCore
import AppKit
import SwiftUI
import XCTest

@MainActor
final class HubDesignSystemTokenTests: XCTestCase {
    /// 2026-07 muted reference spec: compact grouped radii, closer to Cursor/Codex
    /// settings surfaces than raised card slabs.
    func testRadiusTokensMatchSpec() {
        XCTAssertEqual(HubDesignSystem.Radius.shell, 10)
        XCTAssertEqual(HubDesignSystem.Radius.panel, 8)
        XCTAssertEqual(HubDesignSystem.Radius.card, 8)
        XCTAssertEqual(HubDesignSystem.Radius.row, 8)
        XCTAssertEqual(HubDesignSystem.Radius.chip, 7)
        XCTAssertEqual(HubDesignSystem.Radius.button, 7)
        XCTAssertEqual(HubDesignSystem.Radius.popover, 12)
    }

    func testSpacingTokensMatchCompactSpec() {
        XCTAssertEqual(HubDesignSystem.Spacing.shell, 16)
        XCTAssertEqual(HubDesignSystem.Spacing.section, 12)
    }

    func testSizeTokensMatchSpec() {
        XCTAssertEqual(HubDesignSystem.Size.iconButtonSize, 30)
        XCTAssertEqual(HubDesignSystem.Size.chipHeight, 28)
        XCTAssertGreaterThanOrEqual(HubDesignSystem.Size.statusDot, 10)
    }

    /// NMH-036: no shipping UI type below the macOS 10 pt floor. Grip is 14 pt (NMH-077 size);
    /// StatusDot token is ≥ 10. Empty-state art stays 34/36 and is not body type.
    func testUITypeMeetsTenPointFloor() throws {
        XCTAssertGreaterThanOrEqual(HubDesignSystem.Size.statusDot, 10)

        let hub = try String(
            contentsOfFile: "Sources/AppCore/Components/HubDesignSystem.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            hub.contains("public static func micro() -> Font"),
            "Typography.micro() must remain the 10 pt token."
        )
        // NMH-134 supersedes the fixed-size check: micro() now maps to the
        // scalable `.caption` text style (≥ 10 pt, Display text size aware).
        XCTAssertTrue(
            hub.contains(".caption.weight(.medium)"),
            "Typography.micro() must stay ≥ 10 pt via the .caption text style (NMH-134)."
        )

        let pill = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ProjectWorkflowStatus+ArchiveUI.swift",
            encoding: .utf8
        )
        XCTAssertFalse(pill.contains("compact ? 8"))
        XCTAssertFalse(pill.contains("compact ? 9"))
        XCTAssertTrue(pill.contains(".font(.system(size: 10, weight: .semibold))"))
        XCTAssertTrue(pill.contains(".font(.system(size: 10, weight: .medium))"))

        let library = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveSidebarMorePanel.swift",
            encoding: .utf8
        )
        XCTAssertFalse(library.contains(".font(.system(size: 9"))
        XCTAssertTrue(library.contains(".font(.system(size: 10, weight: .semibold))"))

        let downloader = try String(
            contentsOfFile: "Sources/FeatureDownloader/DownloaderView.swift",
            encoding: .utf8
        )
        XCTAssertFalse(downloader.contains(".font(.system(size: 9"))
        XCTAssertTrue(downloader.contains("Image(systemName: \"chevron.up.chevron.down\")"))
        XCTAssertTrue(downloader.contains(".font(.system(size: 10, weight: .semibold))"))

        let grip = try String(
            contentsOfFile: "Sources/AppCore/Components/HubDragAffordance.swift",
            encoding: .utf8
        )
        XCTAssertFalse(grip.contains("size: 8"))
        XCTAssertTrue(grip.contains(".font(.system(size: 14, weight: .bold))"))
        XCTAssertTrue(grip.contains(".accessibilityHidden(true)"))

        let emptyArchive = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            emptyArchive.contains(".font(.system(size: 34, weight: .medium))"),
            "Empty-state archive symbol must stay 34 pt."
        )

        let firstRun = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveFirstRunView.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            firstRun.contains(".font(.system(size: 36, weight: .semibold))"),
            "First-run empty-state symbol must stay 36 pt."
        )
    }

    func testAccentIsNeutralNotTinted() {
        let application = NSApplication.shared
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            guard let appearance = NSAppearance(named: appearanceName) else {
                XCTFail("Missing appearance \(appearanceName.rawValue)")
                continue
            }
            let previous = application.appearance
            application.appearance = appearance
            defer { application.appearance = previous }

            let components = rgbaComponents(HubDesignSystem.Colors.accent)
            XCTAssertNotNil(components, "accent components missing under \(appearanceName.rawValue)")
            XCTAssertLessThan(abs(Double(components!.red) - Double(components!.green)), 0.06)
            XCTAssertLessThan(abs(Double(components!.green) - Double(components!.blue)), 0.06)
        }
    }

    func testSelectedRowTokensUseAccentNotSystemAccent() {
        XCTAssertEqual(
            rgbaComponents(HubDesignSystem.selectedRowFill)?.red,
            rgbaComponents(HubDesignSystem.Colors.accentTint)?.red
        )
        XCTAssertEqual(
            rgbaComponents(HubDesignSystem.selectedRowStroke)?.red,
            rgbaComponents(HubDesignSystem.Colors.selectedStroke)?.red
        )
    }

    /// DS-02: all 14 semantic color roles exposed and named by purpose.
    /// Compile-time presence check — fails to compile if any role is missing.
    func testSemanticPaletteExposesAllRoles() {
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
    }

    /// Motion durations locked per CONTEXT.md (150/250/400ms) with a Reduce Motion path.
    func testMotionDurationsMatchLockedSpec() {
        XCTAssertEqual(HubDesignSystem.Motion.short, 0.15)
        XCTAssertEqual(HubDesignSystem.Motion.medium, 0.25)
        XCTAssertEqual(HubDesignSystem.Motion.long, 0.40)
        XCTAssertEqual(HubDesignSystem.Motion.duration(.short, reduceMotion: true), 0)
        XCTAssertEqual(HubDesignSystem.Motion.duration(.short, reduceMotion: false), 0.15)
    }

    /// DS-05 / NMH-025: ControlState includes `.focused` for quiet-field rings.
    func testControlStateCoversAllSevenCases() throws {
        XCTAssertEqual(HubDesignSystem.ControlState.allCases.count, 8)
        XCTAssertEqual(
            HubDesignSystem.ControlState.allCases,
            [.normal, .hover, .pressed, .selected, .disabled, .warning, .error, .focused]
        )

        let surface = try String(
            contentsOfFile: "Sources/AppCore/Components/HubSurface.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            surface.contains("if level == .field, state == .focused"),
            "Focused fields must take the NMH-025 Palette.focus stroke path."
        )
        XCTAssertTrue(
            surface.contains("shape.strokeBorder(HubDesignSystem.Palette.focus, lineWidth: 2)"),
            "Focused quiet fields must draw a 2 pt Palette.focus ring."
        )

        let quiet = try String(
            contentsOfFile: "Sources/AppCore/Components/HubQuietField.swift",
            encoding: .utf8
        )
        XCTAssertTrue(quiet.contains("textFieldStyle(.plain)"))
        XCTAssertTrue(quiet.contains("@FocusState"))
        XCTAssertTrue(quiet.contains("state: isFocused ? .focused : .normal"))
        XCTAssertFalse(
            quiet.contains("focusEffectDisabled"),
            "Quiet fields must not suppress the keyboard focus effect."
        )
    }

    /// Increase Contrast must not share standard dark RGB. AppKit cannot instantiate
    /// `.accessibilityHighContrastDarkAqua` via `NSAppearance(named:)` (returns nil), so the
    /// match name is injected through `hubDynamicColor(light:dark:lightHigh:darkHigh:matching:)`.
    func testHighContrastSecondaryDiffersFromStandard() throws {
        let light = Color(.sRGB, red: 90 / 255, green: 90 / 255, blue: 98 / 255, opacity: 1)
        let dark = Color(.sRGB, red: 156 / 255, green: 158 / 255, blue: 167 / 255, opacity: 1)
        let lightHigh = Color(.sRGB, red: 60 / 255, green: 60 / 255, blue: 66 / 255, opacity: 1)
        let darkHigh = Color(.sRGB, red: 196 / 255, green: 198 / 255, blue: 206 / 255, opacity: 1)

        let standard = hubDynamicColor(
            light: light,
            dark: dark,
            lightHigh: lightHigh,
            darkHigh: darkHigh,
            matching: .darkAqua
        )
        let increased = hubDynamicColor(
            light: light,
            dark: dark,
            lightHigh: lightHigh,
            darkHigh: darkHigh,
            matching: .accessibilityHighContrastDarkAqua
        )
        XCTAssertNotEqual(standard.redComponent, increased.redComponent, accuracy: 0.002)
        XCTAssertNotEqual(standard.greenComponent, increased.greenComponent, accuracy: 0.002)
        XCTAssertNotEqual(standard.blueComponent, increased.blueComponent, accuracy: 0.002)

        let aqua = hubDynamicColor(
            light: light,
            dark: dark,
            lightHigh: lightHigh,
            darkHigh: darkHigh,
            matching: .aqua
        )
        XCTAssertNotEqual(aqua.redComponent, standard.redComponent, accuracy: 0.002)

        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubDesignSystem.swift",
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("public static let textSecondary"),
            "Palette.textSecondary must remain the shipping token."
        )
        XCTAssertTrue(
            source.contains("darkHigh:  Color(.sRGB, red: 196/255, green: 198/255, blue: 206/255, opacity: 1)"),
            "Palette.textSecondary must ship the Increase Contrast dark pair."
        )
        XCTAssertTrue(
            source.contains("bestMatch(from: hubAppearanceMatchCandidates())"),
            "High-contrast appearances must resolve via bestMatch, not a second ThemeManager."
        )
    }

    /// The legacy `HubDesignSystem.Liquid` namespace (`SurfaceLevel` / `Intent` / `Motion`) is
    /// deleted. It had no production call sites, and the Phase 57 that was meant to remove it was
    /// cancelled when v1.9 phases 52–57 were superseded by reference-glass on `main`.
    /// Radius and motion coverage now lives on the semantic tokens directly, above.
    func testLegacyLiquidNamespaceIsGone() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubDesignSystem.swift",
            encoding: .utf8
        )
        XCTAssertFalse(
            source.contains("public enum Liquid"),
            "HubDesignSystem.Liquid was deleted — do not reintroduce the legacy namespace."
        )
        XCTAssertFalse(
            source.contains("Removed in Phase 57"),
            "Phase 57 was cancelled; deprecation messages must not promise it."
        )
    }
}

private struct RGBAComponents {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
}

@MainActor
private func rgbaComponents(_ color: Color) -> RGBAComponents? {
    guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    return RGBAComponents(
        red: nsColor.redComponent,
        green: nsColor.greenComponent,
        blue: nsColor.blueComponent
    )
}
