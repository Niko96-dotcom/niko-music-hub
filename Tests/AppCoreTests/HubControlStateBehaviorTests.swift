import AppCore
import AppKit
import SwiftUI
import XCTest

@MainActor
final class HubControlStateBehaviorTests: XCTestCase {

    func testCardStatesHostWithoutCrash() {
        for state in HubDesignSystem.ControlState.allCases {
            hostView(
                Text("Test").padding().hubCard(state: state),
                size: CGSize(width: 160, height: 48)
            )
        }
    }

    // MARK: A11Y-07: Reduce Motion zeroes duration

    /// A11Y-07: Motion.duration returns 0 when Reduce Motion is on.
    func testReduceMotionZeroesDuration() {
        XCTAssertEqual(
            HubDesignSystem.Motion.duration(.short, reduceMotion: true), 0,
            "Motion.duration(.short, reduceMotion: true) must be 0 (A11Y-07)"
        )
        XCTAssertEqual(
            HubDesignSystem.Motion.duration(.medium, reduceMotion: true), 0,
            "Motion.duration(.medium, reduceMotion: true) must be 0 (A11Y-07)"
        )
        XCTAssertEqual(
            HubDesignSystem.Motion.duration(.long, reduceMotion: true), 0,
            "Motion.duration(.long, reduceMotion: true) must be 0 (A11Y-07)"
        )
    }

    /// A11Y-07: Motion is NOT zeroed when Reduce Motion is off.
    func testReduceMotionNonZeroWhenOff() {
        XCTAssertEqual(
            HubDesignSystem.Motion.duration(.short, reduceMotion: false), 0.15,
            "Motion.duration(.short, reduceMotion: false) must be 0.15 (A11Y-07)"
        )
        XCTAssertEqual(
            HubDesignSystem.Motion.duration(.medium, reduceMotion: false), 0.25,
            "Motion.duration(.medium, reduceMotion: false) must be 0.25 (A11Y-07)"
        )
        XCTAssertEqual(
            HubDesignSystem.Motion.duration(.long, reduceMotion: false), 0.40,
            "Motion.duration(.long, reduceMotion: false) must be 0.40 (A11Y-07)"
        )
    }

}

@MainActor
private func hostView<V: View>(_ view: V, size: CGSize) {
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
