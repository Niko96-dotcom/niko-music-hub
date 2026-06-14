import Foundation

/// Pure stateless model for the menu bar quick-access menu.
///
/// Provides resolver-driven entries and divider-placement logic without
/// requiring SwiftUI view instantiation, so `AppCoreTests` can assert
/// routing correctness (ROUT-01..05) and degenerate-case behavior (MBAR-04).
public enum MenuBarMenuModel {

    /// Returns the ordered, registry-filtered menu entries from the allowlist.
    /// Delegates to `QuickAccessResolver.resolve` — unregistered tool entries are
    /// omitted; `.revealOutputInbox` always passes through (MBAR-04).
    public static func resolvedEntries(registry: ToolRegistry) -> [QuickAccessEntry] {
        QuickAccessResolver.resolve(
            entries: QuickAccessEntry.allowlist,
            registry: registry
        )
    }

    /// Returns `true` when a native `Divider()` should be placed immediately
    /// before `entry` in the menu. The divider groups tool launcher rows above
    /// the Output Inbox destination row.
    ///
    /// Rules (UI-SPEC):
    /// - Only returns `true` when `entry` has `.revealOutputInbox` command.
    /// - Returns `false` when no `.openTool` rows appear in `entries` (prevents
    ///   a leading separator when only Output Inbox remains — MBAR-04).
    public static func shouldShowDivider(
        before entry: QuickAccessEntry,
        in entries: [QuickAccessEntry]
    ) -> Bool {
        guard case .revealOutputInbox = entry.command else { return false }
        return entries.contains {
            if case .openTool = $0.command { return true }
            return false
        }
    }
}
