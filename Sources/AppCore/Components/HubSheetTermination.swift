import AppKit
import SwiftUI

extension View {
    /// Workflow sheets must let Quit reach the app's shared termination policy.
    /// Quitting still confirms and finishes running work through ADR-019.
    public func hubAllowsApplicationQuit() -> some View {
        background(HubSheetTerminationBridge().frame(width: 0, height: 0))
    }
}

private struct HubSheetTerminationBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> HubSheetTerminationView { HubSheetTerminationView() }
    func updateNSView(_ view: HubSheetTerminationView, context: Context) {}
}

final class HubSheetTerminationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.preventsApplicationTerminationWhenModal = false
    }
}
