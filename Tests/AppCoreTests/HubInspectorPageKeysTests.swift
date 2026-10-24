@testable import AppCore
import AppKit
import SwiftUI
import XCTest

/// `HubInspectorPage` binds a page's Return and Esc keys (design contract §4).
@MainActor
final class HubInspectorPageKeysTests: XCTestCase {
    func testOnlyAnEnabledKeyIsInstalled() {
        XCTAssertEqual(HubPageKey.installed(HubPageKey("Convert") {}, onVisiblePage: true)?.title, "Convert")
        XCTAssertNil(HubPageKey.installed(HubPageKey("Stop After This File", isEnabled: false) {}, onVisiblePage: true))
        XCTAssertNil(HubPageKey.installed(nil, onVisiblePage: true))
    }

    /// The shell keeps a page you left mounted (opacity 0); its keys must not stay bound.
    func testAPageYouLeftInstallsNoKey() {
        XCTAssertNil(HubPageKey.installed(HubPageKey("Convert") {}, onVisiblePage: false))
        XCTAssertNil(HubPageKey.installed(HubPageKey("Stop") {}, onVisiblePage: false))
    }

    func testInstalledKeyRunsThePagesAction() {
        var ran = 0
        HubPageKey.installed(HubPageKey("Start Separation") { ran += 1 }, onVisiblePage: true)?.perform()
        XCTAssertEqual(ran, 1)
    }

    /// AppKit never offers a plain Esc to the Edit ▸ Cancel menu item while the window
    /// is key; the key goes to the window (`sendEvent` here). On the WAV Converter the
    /// first Esc asked for the soft stop, which unbinds the page's cancel key, and the
    /// second Esc then did nothing: the file ran to its end (live check, 2026-10-24).
    /// The page binds the shell's Esc once its own cancel key is disabled.
    func testEscAfterThePagesCancelKeyIsDisabledCancelsWhatEditCancelCancels() throws {
        let fixture = EscapeFixture()
        let page = SoftStopPage()
        let window = fixture.host(page)
        defer { window.close() }

        window.sendEvent(try escapeKey(in: window))
        waitUntil { page.stopRequested }
        XCTAssertTrue(page.stopRequested, "the first Esc runs the page's enabled cancel key")
        XCTAssertEqual(fixture.cancels.count, 0, "the page's cancel key takes Esc before the shell")

        spin()
        window.sendEvent(try escapeKey(in: window))
        waitUntil { fixture.cancels.count == 1 }
        XCTAssertEqual(fixture.cancels.count, 1, "the second Esc cancels the tool's job, as Edit ▸ Cancel does")
    }

    func testEscOnAPageYouLeftLeavesTheJobRunning() throws {
        let fixture = EscapeFixture()
        let window = fixture.host(SoftStopPage(stopRequested: true), onVisiblePage: false)
        defer { window.close() }

        window.sendEvent(try escapeKey(in: window))
        spin()
        XCTAssertEqual(fixture.cancels.count, 0, "only the visible page binds the shell's Esc")
    }

    private func escapeKey(in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
    }

    /// Lets the hosted view render once after a change.
    private func spin(_ seconds: TimeInterval = 0.2) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Runs the main run loop until `condition` holds or two seconds pass.
    private func waitUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}

/// A converter-like tool pane with one running job, as the shell mounts it.
@MainActor
private final class EscapeFixture {
    let cancels = CancelCount()
    let center = ShellJobStatusCenter(jobRunner: JobRunner())
    let tool = ToolMetadata(id: "escape-fixture", displayName: "Fixture", shortLabel: "Fixture",
                            systemImage: "circle", handlesEscape: true)

    init() {
        let cancels = cancels
        center.setExtraJob(
            sourceID: "escape-fixture-job",
            status: ShellJobStatus(id: "escape-fixture-job", title: "Song.wav", cancelActionID: "escape-fixture-job",
                                   sourceToolID: tool.id, cancelTarget: .conversion),
            cancel: { cancels.increment() }
        )
    }

    func host(_ page: SoftStopPage, onVisiblePage: Bool = true) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SoftStopPageView(page: page)
            .environment(\.hubToolIsActive, onVisiblePage)
            .environment(\.hubShellEscape, HubShellEscape(jobStatusCenter: center, tool: tool)))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return window
    }
}

/// The converter's "Stop After This File": enabled until it is asked for.
@MainActor
private final class SoftStopPage: ObservableObject {
    @Published private(set) var stopRequested: Bool

    init(stopRequested: Bool = false) {
        self.stopRequested = stopRequested
    }

    func requestStop() {
        stopRequested = true
    }
}

private struct SoftStopPageView: View {
    @ObservedObject var page: SoftStopPage

    var body: some View {
        HubInspectorPage(
            header: { Text("Fixture") },
            live: { EmptyView() },
            primary: { Color.clear },
            list: { EmptyView() },
            inspector: { EmptyView() },
            action: { Text("Convert") },
            cancelKey: HubPageKey("Stop After This File", isEnabled: !page.stopRequested) { page.requestStop() }
        )
    }
}

private final class CancelCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func increment() {
        lock.withLock { value += 1 }
    }
}
