import AppKit
import SwiftUI

/// Full-size content + transparent titlebar so custom shell chrome isn't doubled by system insets.
struct HubWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(windowFor: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(windowFor: nsView)
    }

    private func configure(windowFor view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}
