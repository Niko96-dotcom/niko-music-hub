@testable import AppCore
import AppKit
import SwiftUI
import XCTest

/// Hosted `HubInspectorPage` chrome-stability regression (contract §2/§4).
///
/// Instantiates the REAL scaffold — never a mirrored fixture layout — with inert
/// fixture slot content, hosted in an `NSHostingView` inside a detached,
/// never-ordered-front `NSWindow` at a fixed 900×700 root. Geometry is reported
/// via `GeometryReader`/background preferences in a named root coordinate space
/// (no screen coordinates, no font-metric assertions); one hosted instance moves
/// through idle → live + secondaries → scrolled-to-tail while header, bounded
/// primary object, and the pinned primary action must not move.
///
/// Offscreen-scroll note: `proxy.scrollTo` drives the scaffold's own ScrollView
/// (via a root `ScrollViewReader`, not a mirrored scroller) without ever calling
/// `makeKeyAndOrderFront`/`orderFront` — the parent owns the shared live GUI and
/// this test must stay offscreen for repeatability. Tail reachability is asserted
/// on real named-space geometry, not pixels, so no visibility is required. If
/// AppKit ever defers programmatic scroll offsets for never-visible windows, the
/// tail-visible wait — not the chrome-stability assertions — is the known-fragile
/// point: report it, never silence it with `XCTSkip` or by ordering the window
/// front.
@MainActor
final class HubInspectorPageLayoutTests: XCTestCase {
    func testLongListAndLiveActionsKeepChromeStableAndTailReachable() {
        let rootWidth: CGFloat = 900
        let rootHeight: CGFloat = 700
        let tolerance: CGFloat = 1.0
        let tailID = "HubInspectorPageLayoutTests.tail"
        let state = LayoutFixtureState()
        let frames = LayoutFrameBox()
        let proxyBox = LayoutProxyBox()

        let root = ScrollViewReader { proxy in
            LayoutFixturePage(state: state, tailID: tailID)
                .frame(width: rootWidth, height: rootHeight)
                .coordinateSpace(name: "HubInspectorPageLayoutTests.root")
                .onPreferenceChange(LayoutRectProbeKey.self) { frames.value = $0 }
                .onAppear { proxyBox.proxy = proxy }
        }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: rootWidth, height: rootHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        defer { window.close() }

        // State A: idle — no live strip, primary action only, 80-row list.
        guard waitFor(
            "initial header/primary/action geometry",
            timeout: 3.0,
            diagnostics: { "have keys: \(frames.value.keys.sorted())" },
            predicate: { Self.hasNonzero(frames.value, keys: ["header", "primary", "actionPrimary", "tail"]) }
        ) else { return }
        guard let headerA = require(frames.value["header"], "header"),
              let primaryA = require(frames.value["primary"], "primary"),
              let actionA = require(frames.value["actionPrimary"], "actionPrimary"),
              let tailA = require(frames.value["tail"], "tail")
        else { return }

        XCTAssertEqual(Double(primaryA.height), 168.0, accuracy: Double(tolerance), "bounded primary object must be 168pt tall")
        XCTAssertGreaterThan(
            Double(tailA.maxY), Double(rootHeight),
            "80-row list must overflow the viewport so scroll reachability is meaningful (tail starts below the fold)"
        )
        assertInsideWindow(actionA, rootWidth: rootWidth, rootHeight: rootHeight, tolerance: tolerance, name: "idle primary action")

        // State B: same instance, live strip on + two secondary actions.
        state.showsLive = true
        state.secondaryCount = 2
        guard waitFor(
            "live + secondary action geometry after state change",
            timeout: 3.0,
            diagnostics: { "have keys: \(frames.value.keys.sorted())" },
            predicate: {
                Self.hasNonzero(
                    frames.value,
                    keys: ["header", "primary", "actionPrimary", "live", "actionSecondary1", "actionSecondary2", "tail"]
                )
            }
        ) else { return }
        guard let headerB = require(frames.value["header"], "header"),
              let primaryB = require(frames.value["primary"], "primary"),
              let actionB = require(frames.value["actionPrimary"], "actionPrimary"),
              let secondary1B = require(frames.value["actionSecondary1"], "actionSecondary1"),
              let secondary2B = require(frames.value["actionSecondary2"], "actionSecondary2")
        else { return }

        assertOriginStable(headerA, headerB, name: "header", tolerance: tolerance)
        assertOriginStable(primaryA, primaryB, name: "primary", tolerance: tolerance)
        XCTAssertEqual(Double(primaryB.height), 168.0, accuracy: Double(tolerance), "live content must not resize the bounded primary object")
        XCTAssertEqual(
            Double(actionB.maxY), Double(actionA.maxY), accuracy: Double(tolerance),
            "pinned primary action bottom must not move when the live strip and secondaries appear"
        )
        assertInsideWindow(actionB, rootWidth: rootWidth, rootHeight: rootHeight, tolerance: tolerance, name: "pinned primary action")
        XCTAssertGreaterThanOrEqual(
            Double(actionB.minY), Double(secondary2B.maxY) - Double(tolerance),
            "primary action must remain the lowest child with secondaries above it (HubPrimaryLastStack pins the first child last)"
        )
        XCTAssertGreaterThanOrEqual(
            Double(secondary2B.minY), Double(secondary1B.maxY) - Double(tolerance),
            "secondaries must stack in order above the primary"
        )

        // State C: scroll the same instance to the tail; chrome must not move.
        guard waitFor("ScrollViewProxy capture", timeout: 3.0, predicate: { proxyBox.proxy != nil }) else { return }
        proxyBox.proxy?.scrollTo(tailID, anchor: .bottom)
        guard waitFor(
            "tail row visible after scrolling to bottom (offscreen window, never ordered front)",
            timeout: 3.0,
            diagnostics: { "tail: \(String(describing: frames.value["tail"]))" },
            predicate: {
                guard let tail = frames.value["tail"], tail.width > 0, tail.height > 0,
                      let primary = frames.value["primary"], primary.width > 0, primary.height > 0
                else { return false }
                return tail.minY >= primary.maxY - tolerance
                    && tail.maxY <= rootHeight - HubToolLayout.bottomPadding + tolerance
            }
        ) else { return }
        guard let headerC = require(frames.value["header"], "header"),
              let primaryC = require(frames.value["primary"], "primary"),
              let actionC = require(frames.value["actionPrimary"], "actionPrimary")
        else { return }

        assertOriginStable(headerB, headerC, name: "header across scroll", tolerance: tolerance)
        assertOriginStable(primaryB, primaryC, name: "primary across scroll", tolerance: tolerance)
        XCTAssertEqual(
            Double(actionC.maxY), Double(actionB.maxY), accuracy: Double(tolerance),
            "scrolling the long list to the tail must not move the pinned primary action"
        )
        XCTAssertEqual(Double(window.frame.width), Double(rootWidth), accuracy: Double(tolerance), "scrolling must not resize the root")
        XCTAssertEqual(Double(window.frame.height), Double(rootHeight), accuracy: Double(tolerance), "scrolling must not resize the root")
    }

    // MARK: - Helpers

    private static func hasNonzero(_ frames: [String: CGRect], keys: [String]) -> Bool {
        keys.allSatisfy { key in
            guard let rect = frames[key] else { return false }
            return rect.width > 0 && rect.height > 0
        }
    }

    @discardableResult
    private func waitFor(
        _ description: String,
        timeout: TimeInterval,
        diagnostics: () -> String = { "" },
        file: StaticString = #filePath,
        line: UInt = #line,
        predicate: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() > deadline {
                XCTFail("Timed out after \(timeout)s waiting for \(description). \(diagnostics())", file: file, line: line)
                return false
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return true
    }

    private func require(_ rect: CGRect?, _ name: String, file: StaticString = #filePath, line: UInt = #line) -> CGRect? {
        guard let rect else {
            XCTFail("Missing hosted geometry for \(name); preference probe never reported", file: file, line: line)
            return nil
        }
        return rect
    }

    private func assertOriginStable(_ before: CGRect, _ after: CGRect, name: String, tolerance: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(after.minX), Double(before.minX), accuracy: Double(tolerance), "\(name) x must stay stable across state", file: file, line: line)
        XCTAssertEqual(Double(after.minY), Double(before.minY), accuracy: Double(tolerance), "\(name) y must stay stable across state", file: file, line: line)
    }

    private func assertInsideWindow(_ rect: CGRect, rootWidth: CGFloat, rootHeight: CGFloat, tolerance: CGFloat, name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(Double(rect.minX), -Double(tolerance), "\(name) must not clip past the leading rail", file: file, line: line)
        XCTAssertGreaterThanOrEqual(Double(rect.minY), -Double(tolerance), "\(name) must not clip above the window", file: file, line: line)
        XCTAssertLessThanOrEqual(Double(rect.maxX), Double(rootWidth) + Double(tolerance), "\(name) must not clip past the trailing rail", file: file, line: line)
        XCTAssertLessThanOrEqual(Double(rect.maxY), Double(rootHeight) + Double(tolerance), "\(name) must stay bounded by the window", file: file, line: line)
    }
}

@MainActor
private final class LayoutFixtureState: ObservableObject {
    @Published var showsLive = false
    @Published var secondaryCount = 0
}

@MainActor
private final class LayoutFrameBox {
    var value: [String: CGRect] = [:]
}

@MainActor
private final class LayoutProxyBox {
    var proxy: ScrollViewProxy?
}

private struct LayoutRectProbeKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private extension View {
    func probe(_ id: String) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: LayoutRectProbeKey.self,
                    value: [id: geo.frame(in: .named("HubInspectorPageLayoutTests.root"))]
                )
            }
        }
    }
}

/// Fixture slot content only — the scaffold is the real `HubInspectorPage`.
/// All strings are inert; no files, settings, or music data.
private struct LayoutFixturePage: View {
    @ObservedObject var state: LayoutFixtureState
    let tailID: String

    var body: some View {
        HubInspectorPage(
            header: {
                ToolHeaderBlock(title: "Fixture Object")
                    .probe("header")
            },
            live: {
                if state.showsLive {
                    Text("Fixture live notice")
                        .probe("live")
                }
            },
            primary: {
                Text("Fixture primary object")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .probe("primary")
            },
            list: {
                HubListSection("Fixture Items", count: 80) {
                    ForEach(0..<79, id: \.self) { index in
                        Text("Fixture row \(index)")
                    }
                    Text("Fixture row 79")
                        .probe("tail")
                        .id(tailID)
                }
            },
            inspector: {
                HubInspectorGroup("Fixture Option") {
                    Text("Fixture value")
                }
            },
            action: {
                HubLabeledButton(icon: "play.fill", label: "Fixture Start", style: .primary, expands: true, action: {})
                    .probe("actionPrimary")
                if state.secondaryCount >= 1 {
                    HubLabeledButton(icon: "stop.fill", label: "Fixture Stop", style: .ghost, expands: true, action: {})
                        .probe("actionSecondary1")
                }
                if state.secondaryCount >= 2 {
                    HubLabeledButton(icon: "arrow.clockwise", label: "Fixture Retry", style: .ghost, expands: true, action: {})
                        .probe("actionSecondary2")
                }
            }
        )
    }
}
