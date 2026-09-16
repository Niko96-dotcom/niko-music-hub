import AppKit
import SwiftUI

/// Full-size content + transparent titlebar so custom shell chrome isn't doubled by system insets.
/// `NSWindow.title` still names the selected tool for the Window menu and Mission Control.
struct HubWindowChromeConfigurator: NSViewRepresentable {
    var windowTitle: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        if view.window != nil {
            configure(windowFor: view)
        } else {
            // Window attaches after makeNSView; apply once it exists instead of
            // re-applying on every update.
            DispatchQueue.main.async {
                self.applyChrome(to: view.window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // LAUNCH-HANG: never unconditionally mutate NSWindow or schedule async
        // work here. Every mutation risks another updateNSView pass; the old
        // always-set + always-dispatch-async pair kept invalidating the view
        // hierarchy. applyChrome is now guarded (no-op when already correct).
        applyChrome(to: nsView.window)
    }

    private func configure(windowFor view: NSView) {
        applyChrome(to: view.window)
    }

    private func applyChrome(to window: NSWindow?) {
        guard let window else { return }
        // Guarded: setting title/style triggers Window-menu / layout work, so
        // only touch the window when a value actually differs.
        if window.title != windowTitle {
            window.title = windowTitle
        }
        if window.titlebarAppearsTransparent != true {
            window.titlebarAppearsTransparent = true
        }
        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        // NMH-130: make the main window frame restorable across relaunch.
        // Default 1280x820 from `.defaultSize` still applies when no saved frame exists.
        if window.isRestorable != true {
            window.isRestorable = true
        }
        if window.identifier != NSUserInterfaceItemIdentifier("hub.main") {
            window.identifier = NSUserInterfaceItemIdentifier("hub.main")
        }
    }
}
