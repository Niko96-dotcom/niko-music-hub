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
        .defaultSize(width: 1_420, height: 860)
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
        HubBrandLogo.installApplicationIcon()
        NSApp.activate(ignoringOtherApps: true)
    }
}
