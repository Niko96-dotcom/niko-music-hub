import Foundation

/// A typed routing command issued by the quick-access menu bar item.
/// Commands resolve to `ToolFeatureID` or panel-visibility state only —
/// they never construct tool views directly (ROUT-07).
public enum QuickAccessCommand: Hashable, Sendable {
    /// Bring the app forward and select the named tool in the sidebar.
    case openTool(ToolFeatureID)
    /// Bring the regular app window forward without changing tool selection.
    /// No-op at the model layer in Phase 46; Phase 47 hooks NSApp.activate.
    case openApp
    /// Show the Output Inbox panel in AppShellView.
    case revealOutputInbox
    /// Open the existing Archive experience and request keyboard focus for search.
    case restoreProject
}
