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

    func testSemanticCardPathHasNoGlassEffectAndDeprecatedAdaptersMarked() throws {
        let cardSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubCard.swift",
            encoding: .utf8
        )
        let liquidSource = try String(
            contentsOfFile: "Sources/AppCore/Components/HubLiquidGlass.swift",
            encoding: .utf8
        )
        // DS-08: the semantic card path has NO glass-effect modifier.
        XCTAssertFalse(cardSource.contains(".glassEffect("), "Semantic HubCard must not use glass-effect modifier (DS-08)")
        // The deprecated Liquid adapters are marked @available(*, deprecated).
        XCTAssertTrue(liquidSource.contains("@available(*, deprecated"), "Liquid adapters must be deprecated")
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

        [
            ".buttonStyle(.glassProminent)",
            ".buttonStyle(.glass)",
            "#available(macOS 26.0, *)",
        ].forEach { required in
            XCTAssertTrue(iconSource.contains(required), "Missing icon button glass source: \(required)")
            XCTAssertTrue(labeledSource.contains(required), "Missing labeled button glass source: \(required)")
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
