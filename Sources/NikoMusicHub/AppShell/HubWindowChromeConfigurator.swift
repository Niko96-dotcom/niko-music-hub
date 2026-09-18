import AppCore
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
        // NMH-129: keep Full Screen available with hidden title bar chrome.
        // Prefer primary (not auxiliary) + managed so toggleFullScreen can enter a Space.
        var behavior = window.collectionBehavior
        behavior.remove(.fullScreenAuxiliary)
        behavior.insert(.managed)
        behavior.insert(.fullScreenPrimary)
        if window.collectionBehavior != behavior {
            window.collectionBehavior = behavior
        }
        // NMH-129: ensure Full Screen style mask
        // Hidden-title-bar scenes can omit bits toggleFullScreen needs.
        let needed: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if !needed.isSubset(of: window.styleMask) {
            window.styleMask.formUnion(needed)
        }
        // NMH-130: make the main window frame restorable across relaunch.
        // Default 1280x820 from `.defaultSize` still applies when no saved frame exists.
        // Identifier alone is not enough — AppKit persists frames via frameAutosaveName.
        if window.isRestorable != true {
            window.isRestorable = true
        }
        if window.identifier != NSUserInterfaceItemIdentifier("hub.main") {
            window.identifier = NSUserInterfaceItemIdentifier("hub.main")
        }
        if window.frameAutosaveName != "hub.main" {
            window.setFrameAutosaveName("hub.main")
        }
        // TRAFFIC-AXIS: one vertical axis for traffic lights + sidebar icons.
        // Delta-based (preserves Apple's internal light spacing on any OS) and
        // stateless: when already on-axis the delta is ~0 and this is a no-op,
        // so it cannot drive an updateNSView loop. Skipped in Full Screen, where
        // the system owns the window controls.
        if !window.styleMask.contains(.fullScreen),
           let close = window.standardWindowButton(.closeButton),
           let mini = window.standardWindowButton(.miniaturizeButton),
           let zoom = window.standardWindowButton(.zoomButton)
        {
            let delta = HubShellLayout.trafficAxisX - close.frame.midX
            if abs(delta) > 0.5 {
                for button in [close, mini, zoom] {
                    button.setFrameOrigin(
                        NSPoint(x: button.frame.origin.x + delta, y: button.frame.origin.y)
                    )
                }
            }
        }
        // LIQUID-KEY: desktop shine-through for the chrome glass (Codex-like).
        // The chrome rails are system glass over the window base — with an opaque
        // window they would only refract our own canvas fill. A transparent window
        // lets them refract the desktop when key; the content column paints its own
        // opaque canvas so only chrome + title strip are affected. Guarded: setting
        // these unconditionally re-triggers display/layout passes (see LAUNCH-HANG).
        if window.isOpaque != false {
            window.isOpaque = false
        }
        if window.backgroundColor != .clear {
            window.backgroundColor = .clear
        }
    }
}
