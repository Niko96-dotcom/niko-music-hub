import AppCore
import AppKit
import AppUpdates
import SwiftUI

@main
struct NikoMusicHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appearanceController: AppAppearanceController

    private let composition: AppComposition

    init() {
        let composition = AppComposition.make()
        self.composition = composition
        AppDelegate.pendingVaultOperationCount = composition.pendingVaultOperationCount
        _appearanceController = StateObject(wrappedValue: composition.appearanceController)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            AppShellView(
                registry: composition.registry,
                context: composition.context,
                router: composition.router,
                shellSession: composition.shellSession
            )
            .preferredColorScheme(appearanceController.preferredColorScheme)
        }
        // Reference chrome: no titlebar band or window title — the glass columns run
        // edge-to-edge and the traffic lights float over the nav column.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_280, height: 820)
        .commands {
            AboutCommand(updateController: composition.updateController)
            HubViewCommands(session: composition.shellSession)
            HubToolsCommands(
                registry: composition.registry,
                router: composition.router,
                session: composition.shellSession
            )
        }

        Settings {
            HubSettingsScene(
                context: composition.context,
                archiveViewModel: composition.archiveViewModel,
                appearanceController: appearanceController,
                updateController: composition.updateController,
                router: composition.router
            )
            .preferredColorScheme(appearanceController.preferredColorScheme)
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

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    static var pendingVaultOperationCount: @MainActor () -> Int = { 0 }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let count = Self.pendingVaultOperationCount()
        guard count > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Project Vault still has \(count) request(s) to finish"
        alert.informativeText = "Keep Music Hub open to finish the queue. Quitting cancels waiting requests and interrupts the running transfer, which may need recovery when you reopen the app. Existing recovery records are kept."
        alert.addButton(withTitle: "Keep Music Hub Open")
        alert.addButton(withTitle: "Quit and Cancel Waiting Requests")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        UILaunchTool.applyFromLaunchArguments()
        #if DEBUG
        if BookmarkRelaunchProofCommands.runIfRequested() {
            return
        }
        _ = ArchiveSmokeCommands.runIfRequested()
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}
