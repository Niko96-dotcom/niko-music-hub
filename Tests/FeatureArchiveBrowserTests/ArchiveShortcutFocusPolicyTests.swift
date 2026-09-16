import AppKit
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
}
