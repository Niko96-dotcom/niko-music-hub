@testable import AppCore
import AppKit
import SwiftUI
import XCTest

@MainActor
final class HubDesignComponentsTests: XCTestCase {
    func testHubLabeledButtonStylesCompile() throws {
        for style in [HubLabeledButtonStyle.primary, .secondary, .ghost] {
            let button = HubLabeledButton(
                icon: "play.fill",
                label: "Play",
                style: style,
                action: {}
            )
            XCTAssertNoThrow(try hostView(button, size: CGSize(width: 120, height: 40)))
        }

        XCTAssertNoThrow(
            try hostView(
                HubIconButton(
                    systemImage: "waveform",
                    accessibilityLabel: "Toolbar",
                    appearance: .toolbar,
                    action: {}
                ),
                size: CGSize(width: 40, height: 40)
            )
        )
        XCTAssertNoThrow(
            try hostView(
                HubIconButton(
                    systemImage: "slider.horizontal.3",
                    accessibilityLabel: "Compact chip",
                    appearance: .compactChip,
                    action: {}
                ),
                size: CGSize(width: 40, height: 40)
            )
        )
        XCTAssertNoThrow(
            try hostView(
                HubChoiceChips(
                    "Adjustment",
                    selection: .constant("original"),
                    choices: [
                        .init("half", label: "½"),
                        .init("original", label: "1×"),
                    ]
                ),
                size: CGSize(width: 160, height: 36)
            )
        )
    }

    func testPressedFillDiffersFromHover() throws {
        XCTAssertEqual(HubPressableButtonStyle.pressedOpacity, 0.92)

        for style in [HubLabeledButtonStyle.secondary, .ghost] {
            let hover = HubLabeledButtonFill.color(style: style, isPressed: false, isHovered: true)
            let pressed = HubLabeledButtonFill.color(style: style, isPressed: true, isHovered: true)
            XCTAssertNotEqual(
                rgbaKey(hover),
                rgbaKey(pressed),
                "\(style) click-and-hold fill must darken vs hover"
            )
        }

        let primaryPressed = HubLabeledButtonFill.color(style: .primary, isPressed: true, isHovered: true)
        XCTAssertEqual(
            rgbaKey(primaryPressed),
            rgbaKey(HubDesignSystem.Palette.accentDeep),
            "Primary press fill uses Palette.accentDeep"
        )

        let toolbarHover = HubIconButtonFill.toolbar(
            prominent: false,
            isSelected: false,
            isPressed: false,
            isHovered: true
        )
        let toolbarPressed = HubIconButtonFill.toolbar(
            prominent: false,
            isSelected: false,
            isPressed: true,
            isHovered: true
        )
        XCTAssertNotEqual(rgbaKey(toolbarHover), rgbaKey(toolbarPressed), "Toolbar icon press fill must differ from hover")

        let chipHover = HubIconButtonFill.compactChip(
            colors: .default,
            isSelected: false,
            isPressed: false,
            isHovered: true
        )
        let chipPressed = HubIconButtonFill.compactChip(
            colors: .default,
            isSelected: false,
            isPressed: true,
            isHovered: true
        )
        XCTAssertNotEqual(rgbaKey(chipHover), rgbaKey(chipPressed), "Compact chip press fill must differ from hover")

        let choiceHover = HubChoiceChipFill.color(isSelected: false, isPressed: false, isHovered: true)
        let choicePressed = HubChoiceChipFill.color(isSelected: false, isPressed: true, isHovered: true)
        XCTAssertNotEqual(rgbaKey(choiceHover), rgbaKey(choicePressed), "Choice chip press fill must differ from hover")

        XCTAssertNotEqual(
            rgbaKey(HubSurfaceFill.color(for: .pressed)),
            rgbaKey(HubSurfaceFill.color(for: .hover)),
            "HubSurface pressed fill must differ from hover"
        )
        XCTAssertNotEqual(
            rgbaKey(HubSurfaceFill.color(for: .pressed)),
            rgbaKey(HubSurfaceFill.color(for: .normal)),
            "HubSurface pressed fill must darken vs normal"
        )
    }

    func testSemanticCardPathHasNoGlassEffect() throws {
        let cardSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubCard.swift",
            encoding: .utf8
        )
        XCTAssertFalse(cardSource.contains(".glassEffect("), "Semantic HubCard must not use glass-effect modifier (DS-08)")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: "Sources/AppCore/Components/HubLiquidGlass.swift"),
            "Deprecated HubLiquidGlass adapters should be removed"
        )
    }

    func testHubButtonsUseNativeGlassStylesWhenAvailable() throws {
        let iconSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubIconButton.swift",
            encoding: .utf8
        )
        let labeledSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubLabeledButton.swift",
            encoding: .utf8
        )

        // Reference-spec buttons are custom neutral controls: solid accent pill for
        // primary, quiet fills otherwise. System glass/bordered styles are FORBIDDEN —
        // they draw boxes and paint the system accent (blue) the references never show.
        [
            ".buttonStyle(.glassProminent)",
            ".buttonStyle(.glass)",
            ".buttonStyle(.borderedProminent)",
            ".buttonStyle(.bordered)",
        ].forEach { forbidden in
            XCTAssertFalse(iconSource.contains(forbidden), "Icon button must not use system style: \(forbidden)")
            XCTAssertFalse(labeledSource.contains(forbidden), "Labeled button must not use system style: \(forbidden)")
        }
        [
            "HubDesignSystem.Palette.accent",
            "HubPressableButtonStyle",
        ].forEach { required in
            XCTAssertTrue(iconSource.contains(required), "Missing icon button reference-style source: \(required)")
            XCTAssertTrue(labeledSource.contains(required), "Missing labeled button reference-style source: \(required)")
        }

        let chipSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubChoiceChips.swift",
            encoding: .utf8
        )
        XCTAssertTrue(chipSource.contains("HubPressableButtonStyle"), "Choice chips must use the shared press style")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: "Sources/AppCore/Components/HubPressableButtonStyle.swift"),
            "HubPressableButtonStyle.swift must exist"
        )
    }
}

private struct RGBAKey: Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
}

private func rgbaKey(_ color: Color) -> RGBAKey? {
    guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    return RGBAKey(
        red: nsColor.redComponent,
        green: nsColor.greenComponent,
        blue: nsColor.blueComponent,
        alpha: nsColor.alphaComponent
    )
}

@MainActor
private func hostView<V: View>(_ view: V, size: CGSize) throws {
    let controller = NSHostingController(rootView: view.frame(width: size.width, height: size.height))
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height)),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = controller.view
    controller.view.layoutSubtreeIfNeeded()
}
