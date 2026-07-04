import AppCore
import AppKit
import SwiftUI
import XCTest

@MainActor
final class HubDesignComponentsTests: XCTestCase {
    func testHubSectionDividerHostsWithoutCrash() {
        XCTAssertNoThrow(try hostView(HubSectionDivider(), size: CGSize(width: 200, height: 12)))
    }

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
            "buttonStyle(.plain)",
        ].forEach { required in
            XCTAssertTrue(iconSource.contains(required), "Missing icon button reference-style source: \(required)")
            XCTAssertTrue(labeledSource.contains(required), "Missing labeled button reference-style source: \(required)")
        }
    }
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
