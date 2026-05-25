import AppKit
import SwiftUI

@main
struct NikoMusicHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let composition = AppComposition.make()

    var body: some Scene {
        WindowGroup {
            AppShellView(
                registry: composition.registry,
                context: composition.context
            )
        }
        .windowResizability(.contentMinSize)
        .commands {
            AboutCommand()
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = ArchiveSmokeCommands.runIfRequested()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
