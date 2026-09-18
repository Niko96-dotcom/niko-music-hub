import AppCore
import FeatureArchiveBrowser
import SwiftUI

struct AppShellView: View {
    private static let activeToolMinWidth: CGFloat = 540
    private static let settingsToolID = ToolFeatureID("settings")

    let registry: ToolRegistry
    let context: ToolContext
    @ObservedObject var router: QuickAccessRouter
    /// Single owner of the selected tool and panel visibility.
    @ObservedObject var shellSession: HubShellSession
    @ObservedObject private var history: HubNavigationHistory
    @Environment(\.openSettings) private var openSettings
    /// Non-observable pane cache; the session's `selectedToolID` drives rendering.
    @State private var toolPaneCache: ToolPaneCache
    /// Router tool requests are one-shot: remember the last one applied so a
    /// window re-appear does not replay it.
    @State private var appliedToolRequestSequence: UInt64 = 0

    @MainActor
    init(
        registry: ToolRegistry,
        context: ToolContext,
        router: QuickAccessRouter,
        shellSession: HubShellSession
    ) {
        self.registry = registry
        self.context = context
        self.router = router
        self.shellSession = shellSession
        self.history = context.navigationHistory
        // No side effects here: the launch tool is resolved (and recorded in
        // history) once by the composition root, before any scene exists.
        _toolPaneCache = State(initialValue: ToolPaneCache(registry: registry, context: context))
    }

    private var selectedToolID: ToolFeatureID? { shellSession.selectedToolID }

    var body: some View {
        ZStack(alignment: .top) {
            // Codex anatomy: there is NO full-width title strip. Each column runs to
            // the window top in its own material (sidebar vibrancy / opaque canvas)
            // and reserves the title row inside itself, so the traffic lights and
            // title controls float on the column tones.
            VStack(spacing: 0) {
                persistenceIssueBanner
                    .padding(.top, columnTopInset)

                // Flush, edge-to-edge split layout — columns sit shoulder-to-shoulder on an
                // inky canvas, separated by hairline dividers (no floating panels / gaps).
                HStack(spacing: 0) {
                    if shellSession.showToolSidebar {
                        ToolSidebarView(
                            context: context,
                            registry: registry,
                            selectedToolID: sidebarSelectedToolID,
                            jobStatusCenter: context.jobStatusCenter
                        )
                        .padding(.top, columnTopInset)
                        .frame(width: HubDesignSystem.Size.navWidth)
                        .hubChromeMaterial()
                        shellDivider
                    }

                    VStack(spacing: 0) {
                        activeToolView
                        ArchivePersistentPlayerView {
                            selectTool(ToolFeatureID("archive-browser"))
                        }
                    }
                        .padding(.top, columnTopInset)
                        .frame(minWidth: Self.activeToolMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .layoutPriority(1)
                        .background(HubDesignSystem.Palette.canvas)

                    if shellSession.inboxEffectiveVisible {
                        shellDivider
                        OutputInboxInspectorView(context: context)
                            .padding(.top, columnTopInset)
                            .frame(width: HubDesignSystem.Size.chromeRailWidth)
                            .hubChromeMaterial()
                    }
                }
                .environment(\.hubTitleRowInset, columnTopInset)
            }

            HubShellTitleBarControls(
                session: shellSession,
                canGoBack: history.canGoBack,
                canGoForward: history.canGoForward,
                toolAccessory: selectedToolID.flatMap { registry.feature(for: $0)?.makeTitleBarAccessory(context: context) },
                onGoBack: { shellSession.goBack() },
                onGoForward: { shellSession.goForward() }
            )
        }
        .ignoresSafeArea(edges: .top)
        .background(HubWindowChromeConfigurator(windowTitle: mainWindowTitle))
        .frame(minWidth: minWindowWidth, minHeight: 720)
        .hubOpensMainWindowFromDock()
        // Esc/⌘. cancel routing reads the selected tool as a scene value, so the
        // Edit-menu items only act while this window is the key scene.
        .focusedSceneValue(\.hubShellCancelContext, HubShellCancelContext(selectedToolID: selectedToolID))
        .onAppear {
            // Drain any pending router state that was set while the window was absent
            // (closed-window case). The menu bar action may fire router.execute() before
            // openWindow() recreates this view; onChange only fires on transitions AFTER
            // subscription, so state set before appearance would be silently dropped.
            applyToolRequest(router.toolRequest)
            if router.revealOutputInbox {
                setOutputInboxVisible(true)
                router.clearRevealOutputInbox()
            }
            if router.archiveSearchFocusRequest > 0 {
                DispatchQueue.main.async {
                    router.consumeArchiveSearchFocusRequest()
                }
            }
            if router.openSettingsPane != nil {
                openSettings()
            }
        }
        .onChange(of: router.toolRequest) { _, request in
            applyToolRequest(request)
        }
        .onChange(of: router.revealOutputInbox) { _, reveal in
            if reveal {
                setOutputInboxVisible(true)
                router.clearRevealOutputInbox()
            }
        }
        .onChange(of: router.prefilledConverterURLs) { _, urls in
            guard !urls.isEmpty else { return }
            selectTool(ToolFeatureID("wav-converter"))
        }
        .onChange(of: router.archiveSearchFocusRequest) { _, request in
            guard request > 0 else { return }
            selectTool(ToolFeatureID("archive-browser"))
            // Defer until the cached Archive pane is visible and can accept focus.
            DispatchQueue.main.async {
                router.consumeArchiveSearchFocusRequest()
            }
        }
        .onChange(of: router.openSettingsPane) { _, pane in
            guard pane != nil else { return }
            openSettings()
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { shellSession.applyWindowWidth(proxy.size.width) }
                    .onChange(of: proxy.size.width) { _, width in
                        shellSession.applyWindowWidth(width)
                    }
            }
        }
        .background(HubShellBackground())
    }

    /// Window menu / Mission Control title from the selected tool. Fallback when unknown.
    private var mainWindowTitle: String {
        HubMainWindowTitle.resolved(selectedToolID: selectedToolID, registry: registry)
    }

    /// Title-row reservation inside each column. When the persistence banner is
    /// up it takes the row instead, so the columns start flush below it.
    private var columnTopInset: CGFloat {
        context.persistenceIssues.isEmpty ? HubShellLayout.titleBarHeight : 0
    }

    /// Full-height hairline that separates flush columns (the reference split-view seam).
    private var shellDivider: some View {
        HubDesignSystem.Palette.separator
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private var minWindowWidth: CGFloat {
        var width: CGFloat = Self.activeToolMinWidth
        if shellSession.showToolSidebar { width += HubDesignSystem.Size.navWidth }
        if shellSession.inboxUserWantsVisible { width += HubDesignSystem.Size.chromeRailWidth }
        return width
    }

    @ViewBuilder
    private var persistenceIssueBanner: some View {
        if !context.persistenceIssues.isEmpty {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
                Label("Persistence running in degraded mode", systemImage: "externaldrive.badge.exclamationmark")
                    .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Colors.warning)
                ForEach(context.persistenceIssues) { issue in
                    Text("\(issue.title): \(issue.message)")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .hubSurface(.card, state: .warning, cornerRadius: HubDesignSystem.Radius.row)
            .padding(HubDesignSystem.Spacing.section)
        }
    }

    private func setOutputInboxVisible(_ visible: Bool) {
        shellSession.setOutputInboxVisible(visible)
    }

    private func applyToolRequest(_ request: QuickAccessToolRequest?) {
        guard let request, request.sequence > appliedToolRequestSequence else { return }
        appliedToolRequestSequence = request.sequence
        selectTool(request.toolID)
    }

    /// Sidebar writes go through `selectTool` so Settings opens the Settings
    /// window instead of replacing the main pane.
    private var sidebarSelectedToolID: Binding<ToolFeatureID?> {
        Binding(
            get: { selectedToolID },
            set: { newValue in
                guard let newValue else {
                    shellSession.setSelectedToolID(nil)
                    return
                }
                selectTool(newValue)
            }
        )
    }

    private func selectTool(_ toolID: ToolFeatureID) {
        if toolID == Self.settingsToolID {
            shellSession.persistSelectedToolID(toolID)
            openSettings()
            return
        }
        shellSession.setSelectedToolID(toolID)
    }

    @ViewBuilder
    private var activeToolView: some View {
        Group {
            if registry.features.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("No tools registered")
                        .font(HubDesignSystem.Typography.screenTitle())
                    Text("Register a ToolFeature in the composition root.")
                        .font(HubDesignSystem.Typography.body())
                        .foregroundStyle(.secondary)
                }
                .hubToolContentColumn()
            } else {
                // Keep visited tools alive so switching tabs is a visibility flip, not a
                // full view/view-model rebuild (Stem Separation / Downloader / Archive).
                ZStack {
                    ForEach(toolPaneCache.mountOrder(selecting: selectedToolID), id: \.self) { toolID in
                        if let toolView = toolPaneCache.ensureMounted(toolID) {
                            let isActive = selectedToolID == toolID
                            toolView
                                .opacity(isActive ? 1 : 0)
                                .allowsHitTesting(isActive)
                                .accessibilityHidden(!isActive)
                                .zIndex(isActive ? 1 : 0)
                                // Hidden panes stay mounted; tell them so app-wide
                                // effects (menu values, key monitors) follow visibility.
                                .environment(\.hubToolIsActive, isActive)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
