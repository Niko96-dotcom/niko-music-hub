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
