import AppKit
import SwiftUI

/// Full-size content + transparent titlebar so custom shell chrome isn't doubled by system insets.
/// `NSWindow.title` still names the selected tool for the Window menu and Mission Control.
struct HubWindowChromeConfigurator: NSViewRepresentable {
    var windowTitle: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(windowFor: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(windowFor: nsView)
    }

    private func configure(windowFor view: NSView) {
        applyChrome(to: view.window)
        DispatchQueue.main.async {
            self.applyChrome(to: view.window)
        }
    }

    private func applyChrome(to window: NSWindow?) {
        guard let window else { return }
        window.title = windowTitle
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
    }
}
