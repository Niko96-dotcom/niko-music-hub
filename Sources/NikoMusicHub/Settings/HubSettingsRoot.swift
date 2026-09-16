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
                    pane: pane
                )
                .tabItem { pane.tabLabel }
                .tag(pane)
            }
        }
        .tabViewStyle(.automatic)
        .navigationTitle(selectedPane.title)
        .modifier(HubSettingsWindowChrome())
        .frame(minWidth: 560, minHeight: 480)
        .hubOpensMainWindowFromDock()
        .onAppear {
            session.refresh()
            consumePendingSettingsPane()
        }
        .onChange(of: router.openSettingsPane) { _, _ in
            consumePendingSettingsPane()
        }
        .onReceive(NotificationCenter.default.publisher(for: .hubOpenSettingsPane)) { note in
            if let pane = note.object as? HubSettingsPane {
                selectedPane = pane
            } else if let raw = note.userInfo?["pane"] as? String,
                      let pane = HubSettingsPane(rawValue: raw) {
                selectedPane = pane
            }
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
