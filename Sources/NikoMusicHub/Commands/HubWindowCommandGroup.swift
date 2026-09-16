import AppKit
import SwiftUI

/// Explicit Window commands for Close / Minimize / Full Screen (NMH-129).
/// With a single `Window`, system Close often stays disabled and still consumes ⌘W.
/// Menu buttons call into `HubWindowChromeActions`, and a local key monitor ensures
/// ⌘W / ⌘M / ⌃⌘F reach those actions.
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
            // Ignore capsLock/numericPad/function bits — they break exact flag equality.
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
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

    private static func forceKey(_ window: NSWindow) {
        // ignoringOtherApps is a no-op on macOS 14+, but activateAllWindows still helps.
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        window.makeMain()
    }

    static func toggleFullScreenMainWindow() {
        guard let window = mainWindow() else { return }
        // Menu-driven invokes often leave keyWindow nil; AppKit then no-ops
        // toggleFullScreen. Force activation + key/main, then toggle after settle.
        forceKey(window)

        let needed: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if !needed.isSubset(of: window.styleMask) {
            window.styleMask.formUnion(needed)
        }

        var behavior = window.collectionBehavior
        behavior.remove(.fullScreenAuxiliary)
        behavior.insert(.managed)
        behavior.insert(.fullScreenPrimary)
        if window.collectionBehavior != behavior {
            window.collectionBehavior = behavior
        }

        let target = window
        DispatchQueue.main.async {
            forceKey(target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                forceKey(target)
                target.toggleFullScreen(nil)
            }
        }
    }
}
