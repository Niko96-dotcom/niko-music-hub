import AppCore
import AppKit
import SwiftUI

@main
struct NikoMusicHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appearanceController: AppAppearanceController

    private let composition: AppComposition

    init() {
        let composition = AppComposition.make()
        self.composition = composition
        _appearanceController = StateObject(wrappedValue: composition.appearanceController)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            AppShellView(
                registry: composition.registry,
                context: composition.context,
                router: composition.router
            )
            .preferredColorScheme(appearanceController.preferredColorScheme)
        }
        // Reference chrome: no titlebar band or window title — the glass columns run
        // edge-to-edge and the traffic lights float over the nav column.
        .windowStyle(.hiddenTitleBar)
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
            .preferredColorScheme(appearanceController.preferredColorScheme)
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
        NSApp.activate()
    }
}
