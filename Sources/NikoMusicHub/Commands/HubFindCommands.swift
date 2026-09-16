import AppCore
import AppKit
import SwiftUI

/// Edit menu Find: the archive search field is this app’s Find (NMH-033).
struct HubFindCommands: Commands {
    let router: QuickAccessRouter

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // CommandGroupPlacement has no .textFinding on the macOS 14.2 SDK.
        // Edit → after Cut/Copy/Paste is the standard Find location.
        CommandGroup(after: .pasteboard) {
            Button("Find") {
                focusArchiveSearch()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Jump to Search Field") {
                focusArchiveSearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }
    }

    private func focusArchiveSearch() {
        router.execute(.focusArchiveSearch)
        openWindow(id: "main")
        NSApp.activate()
    }
}
