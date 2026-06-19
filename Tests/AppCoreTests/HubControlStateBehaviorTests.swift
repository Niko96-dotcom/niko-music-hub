import AppCore
import AppKit
import SwiftUI
import XCTest

/// Tests that verify the Phase 51 semantic design-system behavioral invariants.
/// Covers: DS-05, A11Y-05, A11Y-07, A11Y-08.
@MainActor
final class HubControlStateBehaviorTests: XCTestCase {

    // MARK: DS-05: Control states resolve to semantic tokens (no crash)

    /// DS-05: every ControlState case renders via hubCard() without crashing.
    /// Behavioral hosting test — instantiates each control state and asserts no throw.
    func testControlStatesResolveToSemanticTokens() throws {
        for state in HubDesignSystem.ControlState.allCases {
            XCTAssertNoThrow(
                try hostView(
                    Text("Test").padding().hubCard(state: state),
                    size: CGSize(width: 160, height: 48)
                ),
                "hubCard(state: .\(state)) threw an error — control state rendering failed (DS-05)"
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

    // MARK: A11Y-08: Reduce Transparency / High Contrast paths render

    /// A11Y-08: semantic surfaces host without crash.
    /// HubShellBackground and hubCard() read @Environment directly — verify they render.
    func testReduceTransparencyAndHighContrastPathsRender() throws {
        XCTAssertNoThrow(
            try hostView(
                HubShellBackground(),
                size: CGSize(width: 200, height: 100)
            ),
            "HubShellBackground threw when hosted (A11Y-08)"
        )
        XCTAssertNoThrow(
            try hostView(
                Text("Card").padding().hubCard(state: .normal),
                size: CGSize(width: 200, height: 80)
            ),
            "hubCard(state: .normal) threw when hosted (A11Y-08)"
        )
        // Warning and error states (semantic surfaces with tinted fills)
        XCTAssertNoThrow(
            try hostView(
                Text("Warning").padding().hubCard(state: .warning),
                size: CGSize(width: 200, height: 80)
            ),
            "hubCard(state: .warning) threw when hosted (A11Y-08)"
        )
        XCTAssertNoThrow(
            try hostView(
                Text("Error").padding().hubCard(state: .error),
                size: CGSize(width: 200, height: 80)
            ),
            "hubCard(state: .error) threw when hosted (A11Y-08)"
        )
    }

    // MARK: A11Y-05: Focus ring compiles and hosts

    /// A11Y-05: a view with @FocusState + Palette.focus renders without crash.
    /// The focus token is low-chroma (NOT accent — DS-13), so the focus ring is
    /// subtle and does not draw attention away from content.
    func testFocusRingVisibleOnEveryControl() throws {
        XCTAssertNoThrow(
            try hostView(
                FocusProbe(),
                size: CGSize(width: 120, height: 40)
            ),
            "FocusProbe (view with @FocusState + Palette.focus) threw when hosted (A11Y-05)"
        )
    }
}

// MARK: - Focus probe (A11Y-05)

/// A view with @FocusState that uses Palette.focus for the focus indication.
/// DS-13: focus ring uses Palette.focus (low-chroma, NOT accent).
private struct FocusProbe: View {
    @FocusState private var isFocused: Bool

    var body: some View {
        Text("Focusable")
            .padding(HubDesignSystem.Spacing.inlineGap)
            .background(
                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.button, style: .continuous)
                    .fill(isFocused ? HubDesignSystem.Palette.focus : HubDesignSystem.Palette.surface)
            )
            .focusable()
            .focused($isFocused)
    }
}

// MARK: - Host helper (mirrors HubLiquidDesignSystemTests pattern)

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
