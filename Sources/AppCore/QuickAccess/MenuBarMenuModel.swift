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
        let existingEntries = QuickAccessResolver.resolve(
            entries: QuickAccessEntry.allowlist,
            registry: registry
        )
        let openApp = QuickAccessEntry(
            id: "open-app",
            label: "Open Niko Music Hub",
            systemImage: "macwindow",
            command: .openApp
        )
        let restoreEntry = QuickAccessEntry(
            id: "restore-project",
            label: "Restore Project…",
            systemImage: "arrow.uturn.backward.circle",
            command: .restoreProject
        )
        let quitApp = QuickAccessEntry(
            id: "quit-app",
            label: "Quit Niko Music Hub",
            systemImage: "power",
            command: .quitApp
        )
        return [openApp, restoreEntry] + existingEntries + [quitApp]
    }

    /// Dock menu rows: Open, Archive Browser + registered production tools, Output Inbox.
    /// Settings is omitted (⌘,). Quit stays in the menu-bar extra only.
    public static func dockEntries(registry: ToolRegistry) -> [QuickAccessEntry] {
        let openApp = QuickAccessEntry(
            id: "open-app",
            label: "Open Niko Music Hub",
            systemImage: "macwindow",
            command: .openApp
        )
        let tools = HubToolsShortcutMap.menuMetadata(from: registry.metadata)
            .filter { $0.id != HubToolsShortcutMap.settingsToolID }
            .map { metadata in
                QuickAccessEntry(
                    id: metadata.id.rawValue,
                    label: metadata.displayName,
                    systemImage: metadata.systemImage,
                    command: .openTool(metadata.id)
                )
            }
        let inbox = QuickAccessEntry(
            id: "output-inbox",
            label: "Output Inbox",
            systemImage: "tray.and.arrow.down",
            command: .revealOutputInbox
        )
        return [openApp] + tools + [inbox]
    }

    /// Returns `true` when a native `Divider()` should be placed immediately
    /// before `entry` in the menu.
    ///
    /// Groups: Open · tools · Output Inbox · Quit.
    public static func shouldShowDivider(
        before entry: QuickAccessEntry,
        in entries: [QuickAccessEntry]
    ) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return false }

        switch entry.command {
        case .quitApp:
            return index > 0
        case .revealOutputInbox:
            return entries.contains {
                if case .openTool = $0.command { return true }
                return false
            }
        default:
            if index > 0, case .openApp = entries[index - 1].command {
                return true
            }
            return false
        }
    }
}
