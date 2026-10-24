import AppCore
import AppKit
import NikoMusicCore
import SwiftUI
import XCTest
@testable import FeatureArchiveBrowser

/// The archive's keyboard shortcuts (Esc, Return, Space, arrows) need keyboard
/// focus in the archive pane. A click on a card claims it; a page change that
/// does not come from a click must not leave the keyboard elsewhere.
@MainActor
final class ArchiveKeyboardFocusTests: XCTestCase {
    /// VoiceOver's "Open song detail" (like the Song menu or history Back/Forward)
    /// opens the detail without a click. Esc must still return to the board.
    func testEscClosesADetailOpenedWithoutAClick() throws {
        let context = TestToolContext.make()
        let model = ArchiveBrowserViewModel(context: context, archiveRootWatcher: NoopArchiveRootWatcher())
        let song = Song(folderPath: URL(fileURLWithPath: "/fixture/keyboard-focus/Song", isDirectory: true),
                        originalFolderName: "Focus Song", displayTitle: "Focus Song")
        model.applyCatalogEdit(.load([song]))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ArchiveBrowserView(context: context, viewModel: model)
            .environment(\.hubToolIsActive, true))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        spin()
        // No click since launch: nothing in the archive has the keyboard (the window
        // itself is the first responder).
        window.makeFirstResponder(nil)
        spin()
        XCTAssertTrue(window.firstResponder === window)

        model.openSongDetail(song) // what the card's "Open song detail" action calls
        XCTAssertEqual(model.viewMode, .boardDetail)
        // The page change reaches the view on its next update; with the fix the archive takes
        // the keyboard again. Without it this wait runs out and Esc goes nowhere.
        waitUntil { (window.firstResponder as? NSView)?.isDescendant(of: host) == true }

        window.sendEvent(try escapeKey(in: window))
        waitUntil { model.viewMode == .board }

        XCTAssertEqual(model.viewMode, .board, "Esc must leave a detail that was opened without a click")
    }

    /// The shell keeps the archive pane mounted while another tool is shown. The keys
    /// then belong to the visible page: the hidden archive gives the keyboard up, so
    /// Esc there does not close its song detail (nor stop a Vault transfer or cancel a
    /// scan), and it takes the keyboard back when it is shown again.
    func testHiddenArchiveGivesTheKeyboardUpAndTakesItBackWhenShown() throws {
        let context = TestToolContext.make()
        let model = ArchiveBrowserViewModel(context: context, archiveRootWatcher: NoopArchiveRootWatcher())
        let song = Song(folderPath: URL(fileURLWithPath: "/fixture/keyboard-focus/Song", isDirectory: true),
                        originalFolderName: "Focus Song", displayTitle: "Focus Song")
        model.applyCatalogEdit(.load([song]))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MountedArchivePane(context: context, model: model, isActiveTool: true))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        spin()
        model.openSongDetail(song)
        waitUntil { (window.firstResponder as? NSView)?.isDescendant(of: host) == true }

        host.rootView = MountedArchivePane(context: context, model: model, isActiveTool: false)
        waitUntil { window.firstResponder === window }
        XCTAssertTrue(window.firstResponder === window, "the hidden archive gives the keyboard up")
        window.sendEvent(try escapeKey(in: window))

        host.rootView = MountedArchivePane(context: context, model: model, isActiveTool: true)
        waitUntil { (window.firstResponder as? NSView)?.isDescendant(of: host) == true }
        XCTAssertEqual(model.viewMode, .boardDetail, "Esc on another tool's page must not close the hidden song detail")
        window.sendEvent(try escapeKey(in: window))
        waitUntil { model.viewMode == .board }

        XCTAssertEqual(model.viewMode, .board, "shown again, the archive takes the keyboard back without a click")
    }

    private func escapeKey(in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
        ))
    }

    /// Lets the hosted view render once after it is put in the window.
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

/// The archive pane as the shell mounts it: the visible tool, or hidden behind another one.
private struct MountedArchivePane: View {
    let context: ToolContext
    let model: ArchiveBrowserViewModel
    let isActiveTool: Bool

    var body: some View {
        ArchiveBrowserView(context: context, viewModel: model)
            .environment(\.hubToolIsActive, isActiveTool)
    }
}
