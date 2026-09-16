import Foundation

/// A typed routing command issued by the quick-access menu bar item.
/// Commands resolve to `ToolFeatureID` or panel-visibility state only —
/// they never construct tool views directly (ROUT-07).
public enum QuickAccessCommand: Hashable, Sendable {
    /// Bring the app forward and select the named tool in the sidebar.
    case openTool(ToolFeatureID)
    /// Bring the regular app window forward without changing tool selection.
    case openApp
    /// Show the Output Inbox panel in AppShellView.
    case revealOutputInbox
    /// Open Archive Browser and request keyboard focus for search.
    case focusArchiveSearch
    /// Quit the app via `NSApp.terminate` in the menu view so the vault quit alert still runs.
    case quitApp

    /// Former Restore Project extra command.
    public static var restoreProject: QuickAccessCommand { .focusArchiveSearch }
}
