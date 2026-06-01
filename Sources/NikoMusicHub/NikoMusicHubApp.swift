import AppKit
import SwiftUI

@main
struct NikoMusicHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            AboutCommand()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        _ = ArchiveSmokeCommands.runIfRequested()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showMainWindow() {
        let composition = AppComposition.make()
        let rootView = AppShellView(
            registry: composition.registry,
            context: composition.context
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_360, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Niko Music Hub"
        window.minSize = NSSize(width: 1_220, height: 720)
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
