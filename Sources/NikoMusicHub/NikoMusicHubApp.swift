import AppCore
import AppKit
import AppUpdates
import SwiftUI

@main
struct NikoMusicHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appearanceController: AppAppearanceController
    @StateObject private var shellSession: HubShellSession

    private let composition: AppComposition

    init() {
        let composition = AppComposition.make()
        self.composition = composition
        AppDelegate.pendingVaultOperationCount = composition.pendingVaultOperationCount
        AppDelegate.registry = composition.registry
        AppDelegate.router = composition.router
        _appearanceController = StateObject(wrappedValue: composition.appearanceController)
        _shellSession = StateObject(wrappedValue: composition.shellSession)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            AppShellView(
                registry: composition.registry,
                context: composition.context,
                router: composition.router,
                shellSession: shellSession
            )
            .preferredColorScheme(appearanceController.preferredColorScheme)
        }
        // Hidden title bar: no titlebar band; traffic lights float over the nav column.
        // `NSWindow.title` is still the selected tool (Window menu / Mission Control).
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_280, height: 820)
        .commands {
            AboutCommand(updateController: composition.updateController)
            HubViewCommands(session: shellSession)
            HubToolsCommands(
                registry: composition.registry,
                router: composition.router,
                session: shellSession
            )
            HubHelpCommands(router: composition.router)
        }

        Settings {
            HubSettingsScene(
                context: composition.context,
                archiveViewModel: composition.archiveViewModel,
                appearanceController: appearanceController,
                updateController: composition.updateController,
                router: composition.router,
                shellSession: shellSession
            )
            .preferredColorScheme(appearanceController.preferredColorScheme)
        }

        Window(HubHelpTopics.windowTitle, id: HubHelpTopics.windowID) {
            HubHelpWindow()
                .preferredColorScheme(appearanceController.preferredColorScheme)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 560, height: 640)

        MenuBarExtra(isInserted: showMenuBarExtraBinding) {
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

    private var showMenuBarExtraBinding: Binding<Bool> {
        Binding(
            get: { shellSession.showMenuBarExtra },
            set: { shellSession.setShowMenuBarExtra($0) }
        )
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    static var pendingVaultOperationCount: @MainActor () -> Int = { 0 }
    static var registry = ToolRegistry()
    static var router: QuickAccessRouter?

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

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        HubDockMenu.make(
            registry: Self.registry,
            target: self,
            openApp: #selector(hubDockOpenApp(_:)),
            openTool: #selector(hubDockOpenTool(_:)),
            revealInbox: #selector(hubDockRevealInbox(_:))
        )
    }

    @objc func hubDockOpenApp(_ sender: Any?) {
        Self.router?.execute(.openApp)
        HubMainWindow.reveal()
    }

    @objc func hubDockOpenTool(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        Self.router?.execute(.openTool(ToolFeatureID(raw)))
        HubMainWindow.reveal()
    }

    @objc func hubDockRevealInbox(_ sender: Any?) {
        Self.router?.execute(.revealOutputInbox)
        HubMainWindow.reveal()
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
