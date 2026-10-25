import AppCore
import AppUpdates
import ProjectVaultRuntime
import SwiftUI

/// Paneled Settings window (⌘, / App menu). Shared session so pane switches
/// do not fork immediate-apply state.
struct HubSettingsRoot: View {
    @ObservedObject var router: QuickAccessRouter

    @StateObject private var session: HubSettingsSession
    @State private var selectedPane: HubSettingsPane = .general

    init(
        context: ToolContext,
        appearanceController: AppAppearanceController,
        updateController: AppUpdateController,
        vaultRecoveryService: ProjectVaultRecoveryService?,
        router: QuickAccessRouter,
        shellSession: HubShellSession
    ) {
        self.router = router
        _session = StateObject(
            wrappedValue: HubSettingsSession(
                context: context,
                appearanceController: appearanceController,
                updateController: updateController,
                vaultRecoveryService: vaultRecoveryService,
                shellSession: shellSession
            )
        )
    }

    var body: some View {
        TabView(selection: $selectedPane) {
            ForEach(HubSettingsPaneLayout.order) { pane in
                SettingsView(
                    session: session,
                    router: router,
                    pane: pane
                )
                .tabItem { pane.tabLabel }
                .tag(pane)
            }
        }
        .tabViewStyle(.automatic)
        .navigationTitle(selectedPane.title)
        .modifier(HubSettingsWindowChrome())
        // Fixed width hugs the 680pt form column — no dead space on the right.
        .frame(minWidth: 744, maxWidth: 744, minHeight: 480)
        .hubOpensMainWindowFromDock()
        .onAppear {
            session.refresh()
            consumePendingSettingsPane()
        }
        // Pane deep links arrive only through `router.requestSettingsPane` —
        // pending until this window consumes them, so a request made while the
        // window was closed still lands on the right pane.
        .onChange(of: router.openSettingsPane) { _, _ in
            consumePendingSettingsPane()
        }
    }

    private func consumePendingSettingsPane() {
        guard let pane = router.openSettingsPane else { return }
        selectedPane = pane
        router.clearOpenSettingsPane()
    }
}

private struct HubSettingsWindowChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.presentedWindowToolbarStyle(.unified)
        } else {
            content
        }
    }
}
