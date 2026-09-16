import AppKit
import SwiftUI

/// Explicit Window commands for Close / Minimize / Full Screen (NMH-129).
/// With `.hiddenTitleBar` + single `Window`, system Close often stays disabled and
/// still consumes ⌘W. Menu buttons call into `HubWindowChromeActions`, and a
/// local key monitor ensures ⌘W / ⌘M / ⌃⌘F reach those actions.
struct HubWindowCommandGroup: Commands {
    var body: some Commands {
        CommandGroup(after: .windowList) {
            Button("Close") {
                HubWindowChromeActions.closeMainWindow()
            }
            .keyboardShortcut("w")

            Button("Minimize") {
                HubWindowChromeActions.minimizeMainWindow()
            }
            .keyboardShortcut("m")

            Button("Enter Full Screen") {
                HubWindowChromeActions.toggleFullScreenMainWindow()
            }
            .keyboardShortcut("f", modifiers: [.control, .command])
        }
    }
}

@MainActor
enum HubWindowChromeActions {
    private static var monitor: Any?

    static func installKeyMonitorIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if flags == .command, chars == "w" {
                closeMainWindow()
                return nil
            }
            if flags == .command, chars == "m" {
                minimizeMainWindow()
                return nil
            }
            if flags == [.command, .control], chars == "f" {
                toggleFullScreenMainWindow()
                return nil
            }
            return event
        }
    }

    static func mainWindow() -> NSWindow? {
        let mainID = NSUserInterfaceItemIdentifier("hub.main")
        return NSApp.windows.first(where: { $0.identifier == mainID })
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: \.canBecomeMain)
    }

    static func closeMainWindow() {
        guard let target = mainWindow() else { return }
        if target.styleMask.contains(.closable) {
            target.close()
        } else {
            target.orderOut(nil)
        }
    }

    static func minimizeMainWindow() {
        mainWindow()?.miniaturize(nil)
    }

    static func toggleFullScreenMainWindow() {
        guard let window = mainWindow() else { return }
        if !window.collectionBehavior.contains(.fullScreenPrimary) {
            window.collectionBehavior.insert(.fullScreenPrimary)
        }
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        window.toggleFullScreen(nil)
    }
}
