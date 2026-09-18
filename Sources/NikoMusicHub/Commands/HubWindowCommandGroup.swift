import AppKit
import SwiftUI

/// Key-window-aware replacements for the three window items that were
/// unreliable with the app's singleton SwiftUI `Window` scene (NMH-129).
///
/// These commands intentionally act on `NSApp.keyWindow`: Settings and Help
/// manage themselves, while the main window keeps working after it is reopened.
/// No process-wide event monitor or forced window promotion is involved.
struct HubWindowCommandGroup: Commands {
    var body: some Commands {
        CommandGroup(after: .windowList) {
            Button("Close") {
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut("w")

            Button("Minimize") {
                NSApp.keyWindow?.miniaturize(nil)
            }
            .keyboardShortcut("m")

            Button("Enter Full Screen") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .keyboardShortcut("f", modifiers: [.control, .command])
        }
    }
}
