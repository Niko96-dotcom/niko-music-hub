import AppCore
import AppKit
import AppUpdates
import SwiftUI

@main
struct NikoMusicHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // The App observes only what changes scene structure: the colour scheme
    // and whether the menu bar extra is inserted. Shell state (selected tool,
    // panels) lives on `composition.shellSession`, observed by the shell view
    // and command groups — publishing there must not re-evaluate every scene.
    @StateObject private var appearanceController: AppAppearanceController
    @StateObject private var menuBarExtra: MenuBarExtraState
    @StateObject private var fullScreenState = HubFullScreenState()

    private let composition: AppComposition
    private var shellSession: HubShellSession { composition.shellSession }

    init() {
        // `HubWindowCommandGroup` provides Enter Full Screen with ⌃⌘F; keep
        // AppKit from adding its 🌐F-only duplicate to the View menu. Must be
        // registered before NSApplication builds the menu bar.
        UserDefaults.standard.register(defaults: ["NSFullScreenMenuItemEverywhere": false])
        let composition = AppComposition.make()
        self.composition = composition
        _appearanceController = StateObject(wrappedValue: composition.appearanceController)
        _menuBarExtra = StateObject(wrappedValue: composition.shellSession.menuBarExtra)
        appDelegate.services = HubAppDelegateServices(
            registry: composition.registry,
            router: composition.router,
            pendingVaultOperationCount: composition.pendingVaultOperationCount
        )
    }

    var body: some Scene {
        Window("Niko Music Hub", id: HubMainWindowIdentity.sceneID) {
            AppShellView(
                registry: composition.registry,
                context: composition.context,
                router: composition.router,
                shellSession: shellSession
            )
            .preferredColorScheme(appearanceController.preferredColorScheme)
            // `@AppStorage` reads must hit the same suite as every other preference.
            .defaultAppStorage(composition.userDefaults)
        }
        // Hidden title bar: no titlebar band; traffic lights float over the nav column.
        // `NSWindow.title` is still the selected tool (Window menu / Mission Control).
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_280, height: 820)
        .commands {
            AboutCommand(updateController: composition.updateController)
            HubViewCommands(session: shellSession, history: composition.context.navigationHistory)
            HubWindowCommandGroup(fullScreenState: fullScreenState)
            HubToolsCommands(
                registry: composition.registry,
                router: composition.router,
                session: shellSession
            )
            HubCancelCommands(jobStatusCenter: composition.context.jobStatusCenter)
            HubSongCommands()
            HubFindCommands(router: composition.router)
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
            .defaultAppStorage(composition.userDefaults)
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
                .symbolRenderingMode(.monochrome)
                .accessibilityLabel("Niko Music Hub")
        }
        .menuBarExtraStyle(.menu)
    }

    private var showMenuBarExtraBinding: Binding<Bool> {
        Binding(
            get: { menuBarExtra.isInserted },
            set: { shellSession.setShowMenuBarExtra($0) }
        )
    }
}

/// What the AppKit delegate needs from the composition. Set once from
/// `NikoMusicHubApp.init` (the adaptor instantiates the delegate before the
/// App can hand it anything directly).
@MainActor
struct HubAppDelegateServices {
    let registry: ToolRegistry
    let router: QuickAccessRouter
    let pendingVaultOperationCount: @MainActor () -> Int
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    var services: HubAppDelegateServices?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let count = services?.pendingVaultOperationCount() ?? 0
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
            registry: services?.registry ?? ToolRegistry(),
            target: self,
            openApp: #selector(hubDockOpenApp(_:)),
            openTool: #selector(hubDockOpenTool(_:)),
            revealInbox: #selector(hubDockRevealInbox(_:))
        )
    }

    @objc func hubDockOpenApp(_ sender: Any?) {
        services?.router.execute(.openApp)
        HubMainWindow.reveal()
    }

    @objc func hubDockOpenTool(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        services?.router.execute(.openTool(ToolFeatureID(raw)))
        HubMainWindow.reveal()
    }

    @objc func hubDockRevealInbox(_ sender: Any?) {
        services?.router.execute(.revealOutputInbox)
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
