import AppCore
import AppKit
import SwiftUI
import XCTest

final class HubSharedControlsTests: XCTestCase {
    func testHubToolLayoutConstants() {
        XCTAssertEqual(HubToolLayout.maxContentWidth, 680)
        XCTAssertEqual(HubToolLayout.topPadding, 16)
    }

    func testStatusDotUsesSevenPointFrame() throws {
        try MainActor.assumeIsolated {
            let dot = StatusDot(state: .running)
            let controller = NSHostingController(rootView: dot)
            let size = controller.sizeThatFits(in: NSSize(width: 20, height: 20))
            XCTAssertEqual(size.width, HubDesignSystem.Size.statusDot, accuracy: 0.5)
            XCTAssertEqual(size.height, HubDesignSystem.Size.statusDot, accuracy: 0.5)
        }
    }

    func testArchiveChipUsesHubAccent() {
        let fill = rgbaComponents(HubCompactChipColors.archive.selectedFill)
        let accent = rgbaComponents(HubDesignSystem.Colors.accent)
        XCTAssertNotNil(fill)
        XCTAssertNotNil(accent)
        XCTAssertEqual(Double(fill!.red), Double(accent!.red), accuracy: 0.02)
        XCTAssertEqual(Double(fill!.green), Double(accent!.green), accuracy: 0.02)
        XCTAssertEqual(Double(fill!.blue), Double(accent!.blue), accuracy: 0.02)
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
