import AppCore
import AppKit
import NikoMusicCore
import SwiftUI

/// SwiftUI's container focus can remain true while an AppKit field editor owns
/// keyboard input. Printable song shortcuts must not consume search or note text.
@MainActor
enum ArchiveShortcutFocusPolicy {
    static func allowsSongShortcuts(archiveFocused: Bool, firstResponder: NSResponder?) -> Bool {
        guard archiveFocused, let firstResponder else { return false }
        return !(firstResponder is NSTextView) && !(firstResponder is NSTextField)
    }

    static func allowsSongShortcuts(archiveFocused: Bool) -> Bool {
        guard archiveFocused else { return false }
        let firstResponder = NSApp?.keyWindow?.firstResponder
        return allowsSongShortcuts(archiveFocused: true, firstResponder: firstResponder)
    }

    /// NMH-006: after mode switch / song click, SwiftUI `@FocusState` alone can leave
    /// AppKit firstResponder on the search field editor (or nil). Song arrows/Space and
    /// Option-skip (`canSkipPreview`) require a non-text firstResponder.
    @MainActor
    static func claimArchiveKeyFocus() {
        // NSApp is nil in plain XCTest hosts — never force-unwrap.
        guard let window = NSApp?.keyWindow ?? NSApp?.mainWindow else { return }
        let first = window.firstResponder
        let needsClaim =
            first == nil
            || first is NSTextView
            || first is NSTextField
            || first is NSSearchField
        if needsClaim {
            _ = window.makeFirstResponder(window.contentView)
        }
    }
    /// NMH-006: NSScrollView eats arrow keyDowns before SwiftUI `onMoveCommand` /
    /// `onKeyPress` see them. While the archive is the active tool, convert
    /// plain arrows into `moveSongSelection` and consume the event.
    ///
    /// Scope: only events aimed at the main window (the archive lives there),
    /// and only while no text editor is first responder — arrows inside the
    /// search field or a note must move the caret, not the song highlight.
    /// The pane installs this when it becomes the active tool and removes it
    /// when another tool is shown (`hubToolIsActive`), not on appear/disappear:
    /// cached panes never disappear.
    @MainActor
    private static var arrowKeyMonitor: Any?

    @MainActor
    static func installArchiveArrowKeyMonitor(move: @escaping @MainActor (ArchiveSongMoveDirection) -> Void) {
        removeArchiveArrowKeyMonitor()
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleArrowKeyEvent(event, move: move)
        }
    }

    @MainActor
    static func removeArchiveArrowKeyMonitor() {
        if let arrowKeyMonitor {
            NSEvent.removeMonitor(arrowKeyMonitor)
            self.arrowKeyMonitor = nil
        }
    }

    /// Returns `nil` when the event was consumed as a song move.
    @MainActor
    static func handleArrowKeyEvent(_ event: NSEvent, move: (ArchiveSongMoveDirection) -> Void) -> NSEvent? {
        // Option/Command/Control arrows belong to Song menu (skip) and system chords —
        // never consume them here (NMH-034 / daytime Accept coexistence).
        if !event.modifierFlags.intersection([.option, .command, .control]).isEmpty {
            return event
        }
        guard let direction = arrowDirection(keyCode: event.keyCode) else { return event }
        guard let window = event.window, isMainWindow(window), window.isKeyWindow else { return event }
        if isTextEditing(window.firstResponder) {
            return event
        }
        move(direction)
        return nil
    }

    static func arrowDirection(keyCode: UInt16) -> ArchiveSongMoveDirection? {
        switch keyCode {
        case 126: .up
        case 125: .down
        case 123: .left
        case 124: .right
        default: nil
        }
    }

    static func isTextEditing(_ responder: NSResponder?) -> Bool {
        responder is NSTextView || responder is NSTextField || responder is NSSearchField
    }

    @MainActor
    static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == HubMainWindowIdentity.identifierRawValue
    }
}

/// Actions the Song menu runs while the archive group is focused (NMH-034).
public struct ArchiveSongFocusedActions {
    public let hasSelectedSong: Bool
    public let allowsUnmodifiedShortcuts: Bool
    public let allowsWorkflowMutation: Bool
    /// True when the selected song is the one currently playing (NMH-046 titles).
    public let isPreviewPlaying: Bool
    /// Preview is loaded with a known duration and Option-arrows won't steal caret movement.
    public let canSkipPreview: Bool
    public let playPausePreview: () -> Void
    public let openPreview: () -> Void
    public let openProject: () -> Void
    public let revealInFinder: () -> Void
    public let showVersions: () -> Void
    public let applyWorkflowStatus: (ProjectWorkflowStatus?) -> Void
    public let skipPreviewBack: () -> Void
    public let skipPreviewForward: () -> Void
}

private struct ArchiveSongFocusedActionsKey: FocusedValueKey {
    typealias Value = ArchiveSongFocusedActions
}

extension FocusedValues {
    public var archiveSongActions: ArchiveSongFocusedActions? {
        get { self[ArchiveSongFocusedActionsKey.self] }
        set { self[ArchiveSongFocusedActionsKey.self] = newValue }
    }
}

extension Notification.Name {
    /// Song menu / letter `d`: select the Versions workspace tab (NMH-034).
    static let archiveShowSongVersions = Notification.Name("FeatureArchiveBrowser.archiveShowSongVersions")
}


/// NMH-006: Space must follow keyboard selection, not a stale loaded preview.
enum ArchiveSpacePreviewAction: Equatable {
    case toggleLoaded
    case auditionSelected
    case none

    static func resolve(selectedSongID: String?, loadedSongID: String?, hasLoadedPreview: Bool) -> ArchiveSpacePreviewAction {
        guard let selectedSongID else {
            return hasLoadedPreview ? .toggleLoaded : .none
        }
        if !hasLoadedPreview || loadedSongID != selectedSongID {
            return .auditionSelected
        }
        return .toggleLoaded
    }
}
