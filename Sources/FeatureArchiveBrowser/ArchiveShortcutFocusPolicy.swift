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
}

/// Actions the Song menu runs while the archive group is focused (NMH-034).
public struct ArchiveSongFocusedActions {
    public let hasSelectedSong: Bool
    public let allowsUnmodifiedShortcuts: Bool
    public let allowsWorkflowMutation: Bool
    /// True when the selected song is the one currently playing (NMH-046 titles).
    public let isPreviewPlaying: Bool
    public let playPausePreview: () -> Void
    public let openPreview: () -> Void
    public let openProject: () -> Void
    public let revealInFinder: () -> Void
    public let showVersions: () -> Void
    public let applyWorkflowStatus: (ProjectWorkflowStatus?) -> Void
}

/// Commands read this when `FocusedValue` does not publish into the menu bar (macOS 14.2).
@MainActor
public final class ArchiveSongCommandContext: ObservableObject {
    public static let shared = ArchiveSongCommandContext()
    @Published public private(set) var actions: ArchiveSongFocusedActions?

    public func update(_ actions: ArchiveSongFocusedActions?) {
        self.actions = actions
    }
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
