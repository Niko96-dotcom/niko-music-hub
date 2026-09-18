import AppKit
import Combine
import SwiftUI

/// View ▸ Enter/Exit Full Screen with the classic ⌃⌘F (NMH-129).
///
/// AppKit's auto-inserted item only carries the 🌐F equivalent on current
/// macOS, so it is suppressed (`NSFullScreenMenuItemEverywhere`, registered in
/// `NikoMusicHubApp.init`) and this one stands in. It acts on the key window —
/// Settings and Help toggle themselves, the main window keeps working after it
/// is reopened. Close (⌘W) and Minimize (⌘M) are the system items; no
/// process-wide key monitor.
struct HubWindowCommandGroup: Commands {
    @ObservedObject var fullScreenState: HubFullScreenState

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(fullScreenState.isKeyWindowFullScreen ? "Exit Full Screen" : "Enter Full Screen") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .keyboardShortcut("f", modifiers: [.control, .command])
        }
    }
}

/// Tracks whether the key window is in full screen so the menu title follows
/// it. Commands bodies are not re-evaluated by AppKit window events on their
/// own; this is the one observable they need.
@MainActor
final class HubFullScreenState: ObservableObject {
    @Published private(set) var isKeyWindowFullScreen = false
    private var subscriptions: Set<AnyCancellable> = []

    init() {
        for name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &subscriptions)
        }
    }

    private func refresh() {
        let next = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
        guard next != isKeyWindowFullScreen else { return }
        isKeyWindowFullScreen = next
    }
}
