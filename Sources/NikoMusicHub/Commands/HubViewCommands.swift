import AppCore
import SwiftUI

/// View menu: browser-style Back / Forward (⌘[ / ⌘]) and the panel toggles.
/// The shell is a custom `HStack`, so this replaces `SidebarCommands()` rather
/// than using the NavigationSplitView defaults. The title-bar chevrons are the
/// visible Back/Forward affordance; this is the menu and keyboard path, so the
/// shortcut has one owner and is discoverable.
struct HubViewCommands: Commands {
    @ObservedObject var session: HubShellSession
    @ObservedObject var history: HubNavigationHistory

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button("Back") {
                session.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!history.canGoBack)

            Button("Forward") {
                session.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!history.canGoForward)

            Divider()

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
