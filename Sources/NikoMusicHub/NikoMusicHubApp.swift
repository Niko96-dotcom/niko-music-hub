import AppCore
import AppKit
import SwiftUI

@main
struct NikoMusicHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let composition = AppComposition.make()

    var body: some Scene {
        WindowGroup(id: "main") {
            AppShellView(
                registry: composition.registry,
                context: composition.context,
                router: composition.router
            )
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_280, height: 820)
        .commands {
            AboutCommand()
        }

        MenuBarExtra {
            MenuBarMenuView(
                entries: MenuBarMenuModel.resolvedEntries(registry: composition.registry),
                router: composition.router
            )
        } label: {
            Image(systemName: "waveform")
                .accessibilityLabel("Niko Music Hub")
        }
        .menuBarExtraStyle(.menu)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UILaunchTool.applyFromLaunchArguments()
        #if DEBUG
        _ = ArchiveSmokeCommands.runIfRequested()
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
