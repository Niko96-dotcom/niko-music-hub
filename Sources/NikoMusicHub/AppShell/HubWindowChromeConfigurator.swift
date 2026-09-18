import AppCore
import AppKit
import SwiftUI

/// Full-size content + transparent titlebar so custom shell chrome isn't doubled by system insets.
/// `NSWindow.title` still names the selected tool for the Window menu and Mission Control.
struct HubWindowChromeConfigurator: NSViewRepresentable {
    var windowTitle: String

    /// Per-window-content glue: remembers whether the launch first responder
    /// has been cleared (see applyChrome). Lives exactly as long as this
    /// representable's identity — the shell root — so a reopened window gets
    /// a fresh clear and a stale window identity can never be confused with a
    /// new window (which a process-wide set of `ObjectIdentifier`s could).
    final class Coordinator {
        var didClearInitialFocus = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The window attaches after makeNSView returns; apply once it exists
        // instead of re-applying on every update.
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            self.applyChrome(to: view.window, coordinator: coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // LAUNCH-HANG: never unconditionally mutate NSWindow or schedule async
        // work here. Every mutation risks another updateNSView pass; the old
        // always-set + always-dispatch-async pair kept invalidating the view
        // hierarchy. applyChrome is now guarded (no-op when already correct).
        applyChrome(to: nsView.window, coordinator: context.coordinator)
    }

    private func applyChrome(to window: NSWindow?, coordinator: Coordinator) {
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
        let identifier = NSUserInterfaceItemIdentifier(HubMainWindowIdentity.identifierRawValue)
        if window.identifier != identifier {
            window.identifier = identifier
        }
        if window.frameAutosaveName != identifier.rawValue {
            window.setFrameAutosaveName(identifier.rawValue)
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
            // Vertical: centre the lights on the 44pt title row. The buttons live in
            // AppKit's titlebar view (NOT flipped, ~28pt tall), so measure their
            // distance from the window top through that view's bounds instead of
            // assuming a flipped theme frame (that assumption pushed them UP).
            let delta = HubShellLayout.trafficAxisX - close.frame.midX
            var deltaY: CGFloat = 0
            if let bar = close.superview {
                let fromTop = bar.isFlipped ? close.frame.midY : bar.bounds.height - close.frame.midY
                let wanted = HubShellLayout.titleBarAxisY - fromTop
                deltaY = bar.isFlipped ? wanted : -wanted
            }
            if abs(delta) > 0.5 || abs(deltaY) > 0.5 {
                for button in [close, mini, zoom] {
                    button.setFrameOrigin(
                        NSPoint(x: button.frame.origin.x + delta, y: button.frame.origin.y + deltaY)
                    )
                }
            }
        }
        // No launch focus ring: SwiftUI hands initial key focus to the first
        // `.focusable()` control (the sidebar toggle), which draws our focus ring
        // on a window nobody has tabbed into yet. Clear it once; Tab still enters
        // the key-view loop from the top. Only the shell hosts this configurator,
        // so the Settings window (system controls) is untouched.
        if !coordinator.didClearInitialFocus {
            coordinator.didClearInitialFocus = true
            DispatchQueue.main.async {
                window.makeFirstResponder(nil)
            }
        }
        // Standard opaque window: the rails are `.sidebar` vibrancy blended behind
        // the window, which AppKit composites for opaque windows exactly like a
        // NavigationSplitView sidebar. Guarded (see LAUNCH-HANG).
        if window.isOpaque != true {
            window.isOpaque = true
        }
    }
}
