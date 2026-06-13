import AppCore
import AppKit
import SwiftUI
import XCTest

final class HubDesignSystemTokenTests: XCTestCase {
    func testRadiusTokensMatchSpec() {
        XCTAssertEqual(HubDesignSystem.Radius.shell, 14)
        XCTAssertEqual(HubDesignSystem.Radius.panel, 12)
        XCTAssertEqual(HubDesignSystem.Radius.button, 8)
    }

    func testSpacingTokensMatchCompactSpec() {
        XCTAssertEqual(HubDesignSystem.Spacing.shell, 8)
        XCTAssertEqual(HubDesignSystem.Spacing.section, 20)
    }

    func testSizeTokensMatchSpec() {
        XCTAssertEqual(HubDesignSystem.Size.iconButtonSize, 30)
        XCTAssertEqual(HubDesignSystem.Size.statusDot, 7)
    }

    func testAccentColorUsesSystemAccent() {
        let components = rgbaComponents(HubDesignSystem.Colors.accent)
        let systemComponents = rgbaComponents(.accentColor)
        XCTAssertNotNil(components)
        XCTAssertNotNil(systemComponents)
        XCTAssertEqual(Double(components!.red), Double(systemComponents!.red), accuracy: 0.02)
        XCTAssertEqual(Double(components!.green), Double(systemComponents!.green), accuracy: 0.02)
        XCTAssertEqual(Double(components!.blue), Double(systemComponents!.blue), accuracy: 0.02)
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

    func testLiquidStudioGlassTokensExposeFoundationScale() {
        XCTAssertEqual(HubDesignSystem.Liquid.SurfaceLevel.allCases, [.backdrop, .panel, .card, .field, .chip])
        XCTAssertEqual(HubDesignSystem.Liquid.Intent.allCases, [.normal, .hover, .selected, .disabled, .warning, .error])
        XCTAssertEqual(HubDesignSystem.Liquid.SurfaceLevel.panel.cornerRadius, HubDesignSystem.Radius.panel)
        XCTAssertEqual(HubDesignSystem.Liquid.SurfaceLevel.chip.cornerRadius, HubDesignSystem.Radius.chip)
        XCTAssertGreaterThan(HubDesignSystem.Liquid.Depth.shadowRadius(for: .panel), 0)
        XCTAssertGreaterThan(HubDesignSystem.Liquid.Stroke.width(for: .selected), 1)
        XCTAssertEqual(
            HubDesignSystem.Liquid.Motion.duration(reduceMotion: true),
            HubDesignSystem.Liquid.Motion.disabledResponse
        )
    }

    func testLiquidReferenceContractNamesApprovedAndExcludedAssets() {
        XCTAssertTrue(
            HubDesignSystem.Reference.approvedAssets.contains("tmp/mythos-reference/contact_sheet.png")
        )
        XCTAssertTrue(
            HubDesignSystem.Reference.approvedAssets.contains("output/imagegen/niko-music-hub-liquid-glass-direction.png")
        )
        XCTAssertTrue(HubDesignSystem.Reference.translationNote.contains("MythOS"))
        XCTAssertTrue(HubDesignSystem.Reference.excludedReference.contains("NeuralNote/laptop"))
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
