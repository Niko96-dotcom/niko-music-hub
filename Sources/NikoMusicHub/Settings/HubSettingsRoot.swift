import AppCore
import AppUpdates
import FeatureArchiveBrowser
import SwiftUI

/// Paneled Settings window (⌘, / App menu). Shared session so pane switches
/// do not fork immediate-apply state.
struct HubSettingsRoot: View {
    @ObservedObject var archiveViewModel: ArchiveBrowserViewModel
    @ObservedObject var router: QuickAccessRouter

    @StateObject private var session: HubSettingsSession
    @State private var selectedPane: HubSettingsPane = .general

    init(
        context: ToolContext,
        archiveViewModel: ArchiveBrowserViewModel,
        appearanceController: AppAppearanceController,
        updateController: AppUpdateController,
        router: QuickAccessRouter,
        shellSession: HubShellSession
    ) {
        self.archiveViewModel = archiveViewModel
        self.router = router
        _session = StateObject(
            wrappedValue: HubSettingsSession(
                context: context,
                appearanceController: appearanceController,
                updateController: updateController,
                shellSession: shellSession
            )
        )
    }

    var body: some View {
        TabView(selection: $selectedPane) {
            ForEach(HubSettingsPaneLayout.order) { pane in
                SettingsView(
                    session: session,
                    archiveViewModel: archiveViewModel,
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
