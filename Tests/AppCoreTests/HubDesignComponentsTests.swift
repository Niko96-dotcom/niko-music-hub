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

    func testChoiceChipsWrapAtNarrowWidthAndMeetDefaultHeight() throws {
        XCTAssertEqual(HubDesignSystem.Size.chipHeight, 28)

        let chips = HubChoiceChips(
            "Appearance",
            selection: .constant("followSystem"),
            choices: [
                .init("followSystem", label: "Follow System"),
                .init("light", label: "Light"),
                .init("dark", label: "Dark"),
            ]
        )

        let wideHeight = try hostedLaidOutHeight(chips, width: 480)
        XCTAssertGreaterThanOrEqual(wideHeight, HubDesignSystem.Size.chipHeight)
        XCTAssertLessThan(
            wideHeight,
            HubDesignSystem.Size.chipHeight * 2,
            "Wide proposal must keep Appearance chips on one row"
        )

        let narrowHeight = try hostedLaidOutHeight(chips, width: 72)
        XCTAssertGreaterThan(
            narrowHeight,
            HubDesignSystem.Size.chipHeight + 4,
            "Narrow proposal must wrap chips onto additional rows instead of clipping"
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
            rgbaKey(HubDesignSystem.Palette.indicatorDeep),
            "Primary press fill uses Palette.indicatorDeep (warm-accent test run)"
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

    func testDesignSystemPreviewForcesAppearanceVariants() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubDesignSystemPreview.swift",
            encoding: .utf8
        )
        for title in [
            "Design System · Light",
            "Design System · Dark",
            "Design System · Increased Contrast",
            "Design System · Reduce Transparency",
        ] {
            XCTAssertTrue(
                source.contains("#Preview(\"\(title)\""),
                "Missing forced preview: \(title)"
            )
        }
        XCTAssertTrue(source.contains(".preferredColorScheme(.light)"), "Missing light forcing")
        XCTAssertTrue(source.contains(".preferredColorScheme(.dark)"), "Missing dark forcing")
        // NMH-078 deviation: FIX-SPECS spells the public read-only keys
        // (`\.colorSchemeContrast`, `\.accessibilityReduceTransparency`), which do not
        // compile as `.environment` arguments on this SDK. The previews force the settable
        // backing stores instead (verified at runtime to propagate to the public keys).
        XCTAssertTrue(
            source.contains(".environment(\\._colorSchemeContrast, .increased)"),
            "Missing increased-contrast forcing"
        )
        XCTAssertTrue(
            source.contains(".environment(\\._accessibilityReduceTransparency, true)"),
            "Missing reduce-transparency forcing"
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
        }
        // Warm-accent test run: primary labeled buttons wear Palette.indicator.
        [
            "HubDesignSystem.Palette.indicator",
            "HubPressableButtonStyle",
        ].forEach { required in
            XCTAssertTrue(labeledSource.contains(required), "Missing labeled button reference-style source: \(required)")
        }

        let chipSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubChoiceChips.swift",
            encoding: .utf8
        )
        XCTAssertTrue(chipSource.contains("HubPressableButtonStyle"), "Choice chips must use the shared press style")
        XCTAssertTrue(
            chipSource.contains("HubChoiceChipFlowLayout"),
            "Choice chips must wrap with a flow layout when the row does not fit"
        )
        XCTAssertTrue(
            chipSource.contains(".fixedSize()"),
            "Chips must keep intrinsic width so the row wraps instead of clipping labels"
        )
        XCTAssertTrue(
            chipSource.contains("HubDesignSystem.Motion.duration(.short, reduceMotion: reduceMotion)"),
            "Choice-chip hover must gate on Reduce Motion"
        )
        XCTAssertTrue(
            chipSource.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"),
            "Selected chip must keep the isSelected trait"
        )
        XCTAssertFalse(
            chipSource.contains("Picker"),
            "Do not rewrite HubChoiceChips as Picker(.segmented)"
        )
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

private struct ChipHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChipHeightProbe<Content: View>: View {
    let width: CGFloat
    @Binding var height: CGFloat
    let content: Content

    var body: some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: ChipHeightPreferenceKey.self, value: geo.size.height)
                }
            }
            .onPreferenceChange(ChipHeightPreferenceKey.self) { height = $0 }
            .frame(width: width, alignment: .leading)
    }
}

private final class ChipHeightBox {
    var value: CGFloat = 0
}

@MainActor
private func hostedLaidOutHeight<V: View>(_ view: V, width: CGFloat) throws -> CGFloat {
    let box = ChipHeightBox()
    let probe = ChipHeightProbe(
        width: width,
        height: Binding(
            get: { box.value },
            set: { box.value = $0 }
        ),
        content: view
    )
    let host = NSHostingView(rootView: probe)
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: NSSize(width: width, height: 400)),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    defer { window.close() }
    return box.value
}
