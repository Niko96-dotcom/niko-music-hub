import AppKit
import SwiftUI
@testable import FeatureArchiveBrowser
import XCTest

@MainActor
final class ArchiveShortcutFocusPolicyTests: XCTestCase {
    func testSearchAndMetadataEditorsKeepPrintableKeysEvenWithStaleContainerFocus() {
        let fieldEditor = NSTextView()
        fieldEditor.isFieldEditor = true
        for responder: NSResponder in [fieldEditor, NSTextView(), NSTextField(), NSSearchField()] {
            XCTAssertFalse(ArchiveShortcutFocusPolicy.allowsSongShortcuts(archiveFocused: true, firstResponder: responder))
        }
    }

    func testFocusedArchiveKeepsSongShortcutsOutsideTextEditing() {
        XCTAssertTrue(ArchiveShortcutFocusPolicy.allowsSongShortcuts(archiveFocused: true, firstResponder: NSView()))
        XCTAssertFalse(ArchiveShortcutFocusPolicy.allowsSongShortcuts(archiveFocused: false, firstResponder: NSView()))
        XCTAssertFalse(ArchiveShortcutFocusPolicy.allowsSongShortcuts(archiveFocused: true, firstResponder: nil))
        XCTAssertFalse(ArchiveShortcutFocusPolicy.allowsSongShortcuts(archiveFocused: false))
    }

    func testShowVersionsNotificationNameIsStable() {
        XCTAssertEqual(
            Notification.Name.archiveShowSongVersions.rawValue,
            "FeatureArchiveBrowser.archiveShowSongVersions"
        )
    }

    /// Space typed into the search field (or a metadata/notes field) is text:
    /// the field editor keeps first responder, even when SwiftUI's container
    /// focus still reports the archive. "neon hk" must not end as "neon".
    func testSpaceNeverTakesFocusFromTextEditing() throws {
        for archiveFocused in [false, true] {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            defer { window.orderOut(nil) }
            let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 24))
            window.contentView?.addSubview(field)
            XCTAssertTrue(window.makeFirstResponder(field))
            let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
            XCTAssertTrue(editor.isFieldEditor)

            var played = false
            let result = ArchiveShortcutFocusPolicy.handleSpaceKey(archiveFocused: archiveFocused, in: window) {
                played = true
                return true
            }

            XCTAssertEqual(result, .ignored, "archiveFocused=\(archiveFocused)")
            XCTAssertFalse(played, "archiveFocused=\(archiveFocused)")
            XCTAssertTrue(window.firstResponder === editor, "archiveFocused=\(archiveFocused): Space stole focus from the field")
        }
    }

    func testSpacePlaysPreviewWhenBoardOwnsKeyboard() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        _ = window.makeFirstResponder(nil)

        var plays = 0
        let toggle = { plays += 1; return true }
        XCTAssertEqual(ArchiveShortcutFocusPolicy.handleSpaceKey(archiveFocused: true, in: window, playPause: toggle), .handled)
        XCTAssertEqual(plays, 1)
        XCTAssertEqual(ArchiveShortcutFocusPolicy.handleSpaceKey(archiveFocused: false, in: window, playPause: toggle), .ignored)
        XCTAssertEqual(ArchiveShortcutFocusPolicy.handleSpaceKey(archiveFocused: true, in: nil, playPause: toggle), .ignored)
        XCTAssertEqual(plays, 1)
        XCTAssertEqual(ArchiveShortcutFocusPolicy.handleSpaceKey(archiveFocused: true, in: window) { false }, .ignored)
    }

    func testArchiveSpaceHandlerRoutesThroughPolicyWithoutClaimingFocus() throws {
        let browser = try String(contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift", encoding: .utf8)
        let start = try XCTUnwrap(browser.range(of: ".onKeyPress(.space) {"))
        let tail = browser[start.upperBound...]
        let end = try XCTUnwrap(tail.range(of: ".sheet("))
        let handler = tail[..<end.lowerBound]
        XCTAssertTrue(handler.contains("ArchiveShortcutFocusPolicy.handleSpaceKey("))
        XCTAssertFalse(handler.contains("claimArchiveKeyFocus"))
    }

    func testClaimArchiveKeyFocusIsSafeWithoutKeyWindow() {
        // Smoke: no key window in unit tests — must not trap.
        ArchiveShortcutFocusPolicy.claimArchiveKeyFocus()
        XCTAssertFalse(ArchiveShortcutFocusPolicy.allowsSongShortcuts(archiveFocused: true, firstResponder: nil))
    }
}
