import AppCore
import AppKit
import SwiftUI

/// Compact menu bar quick-access menu content (MBAR-02).
///
/// Renders one `Button` row per resolved `QuickAccessEntry`. Each button action
/// dispatches via the router (ROUT-07), re-opens the main window via the
/// `openWindow` environment action if it was closed (window-reopen decision), and
/// brings the app forward via `NSApp` activate (MBAR-03). A `Divider()` separates
/// tool launcher rows from the Output Inbox row when at least one tool row is
/// present (UI-SPEC / MBAR-04).
struct MenuBarMenuView: View {
    let entries: [QuickAccessEntry]
    // Intentionally a plain stored reference, not @ObservedObject. This view only
    // dispatches actions via router.execute() — it never reads router state for
    // display. If a future change needs to reflect router state in menu row
    // appearance (e.g., a checkmark on the active tool), convert to:
    // @ObservedObject var router: QuickAccessRouter
    let router: QuickAccessRouter

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(entries) { entry in
            if MenuBarMenuModel.shouldShowDivider(before: entry, in: entries) {
                Divider()
            }
            Button {
                router.execute(entry.command)
                // Re-open the main WindowGroup (id "main") if the user closed it —
                // activate alone does not restore a closed window.
                openWindow(id: "main")
                NSApp.activate()
            } label: {
                Label(entry.label, systemImage: entry.systemImage)
            }
        }
    }
}
