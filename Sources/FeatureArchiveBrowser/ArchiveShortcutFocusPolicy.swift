import AppKit

/// SwiftUI's container focus can remain true while an AppKit field editor owns
/// keyboard input. Printable song shortcuts must not consume search or note text.
@MainActor
enum ArchiveShortcutFocusPolicy {
    static func allowsSongShortcuts(archiveFocused: Bool, firstResponder: NSResponder?) -> Bool {
        guard archiveFocused, let firstResponder else { return false }
        return !(firstResponder is NSTextView) && !(firstResponder is NSTextField)
    }
}
