import AppCore
import AppKit
import SwiftUI
import XCTest

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
        XCTAssertEqual(HubDesignSystem.Size.statusDot, 7)
    }

    func testAccentIsNeutralNotTinted() {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: appearanceName)!
            let previous = NSApp.appearance
            NSApp.appearance = appearance
            defer { NSApp.appearance = previous }

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

    func testTypographySurfaceIncludesExpandedScale() {
        _ = HubDesignSystem.Typography.display()
        _ = HubDesignSystem.Typography.screenTitle()
        _ = HubDesignSystem.Typography.sectionTitle()
        _ = HubDesignSystem.Typography.body()
        _ = HubDesignSystem.Typography.bodySmall()
        _ = HubDesignSystem.Typography.caption()
        _ = HubDesignSystem.Typography.micro()
        _ = HubDesignSystem.Typography.mono()
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

    /// DS-05: ControlState enum covers all 7 interactive states.
    func testControlStateCoversAllSevenCases() {
        XCTAssertEqual(HubDesignSystem.ControlState.allCases.count, 7)
        XCTAssertEqual(
            HubDesignSystem.ControlState.allCases,
            [.normal, .hover, .pressed, .selected, .disabled, .warning, .error]
        )
    }

    /// Liquid namespace deprecated in Plan 02 (deleted in Phase 57). Only
    /// `Intent` / `SurfaceLevel` / `Motion` remain as deprecated shims — the decorative
    /// sub-namespaces (Prismatic / AccessibilityFallback / Depth / SurfaceFill / Stroke)
    /// were deleted because the deprecated adapters now delegate to semantic `hubCard()` /
    /// `Palette.*`. These assertions verify the surviving shims still compile so
    /// `HubLiquidGlass.swift` / `AppShellView.swift` / `ToolSidebarView.swift` keep working.
    func testLiquidStudioGlassTokensExposeFoundationScale() {
        XCTAssertEqual(HubDesignSystem.Liquid.SurfaceLevel.allCases, [.backdrop, .panel, .card, .field, .chip])
        XCTAssertEqual(HubDesignSystem.Liquid.Intent.allCases, [.normal, .hover, .selected, .disabled, .warning, .error])
        XCTAssertEqual(HubDesignSystem.Liquid.SurfaceLevel.panel.cornerRadius, HubDesignSystem.Radius.panel)
        XCTAssertEqual(HubDesignSystem.Liquid.SurfaceLevel.chip.cornerRadius, HubDesignSystem.Radius.chip)
        XCTAssertEqual(
            HubDesignSystem.Liquid.Motion.duration(reduceMotion: true),
            HubDesignSystem.Liquid.Motion.disabledResponse
        )
    }
}

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
