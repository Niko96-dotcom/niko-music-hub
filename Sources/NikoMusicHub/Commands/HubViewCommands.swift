import AppCore
import SwiftUI

/// View-menu panel toggles. The shell is a custom `HStack`, so this replaces
/// `SidebarCommands()` rather than using the NavigationSplitView defaults.
struct HubViewCommands: Commands {
    @ObservedObject var session: HubShellSession

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(session.showToolSidebar ? "Hide Tools Sidebar" : "Show Tools Sidebar") {
                session.toggleToolSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button(session.showOutputInbox ? "Hide Output Inbox" : "Show Output Inbox") {
                session.toggleOutputInbox()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
