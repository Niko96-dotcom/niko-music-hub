import AppCore
import FeatureArchiveBrowser
import SwiftUI

struct AppShellView: View {
    private static let activeToolMinWidth: CGFloat = 540
    private static let settingsToolID = ToolFeatureID("settings")

    let registry: ToolRegistry
    let context: ToolContext
    @ObservedObject var router: QuickAccessRouter
    @ObservedObject var shellSession: HubShellSession
    @Environment(\.openSettings) private var openSettings
    @StateObject private var toolPaneCache: ToolPaneCache

    @State private var selectedToolID: ToolFeatureID?

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
        let initialToolID = shellSession.restoreSelectedToolID(registry: registry)
        _toolPaneCache = StateObject(
            wrappedValue: ToolPaneCache(
                registry: registry,
                context: context,
                initialToolID: initialToolID
            )
        )
        _selectedToolID = State(initialValue: initialToolID)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                persistenceIssueBanner

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
                        .frame(minWidth: Self.activeToolMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .layoutPriority(1)
                        .background(HubDesignSystem.Palette.canvas)

                    if shellSession.inboxEffectiveVisible {
                        shellDivider
                        OutputInboxInspectorView(context: context)
                            .frame(minWidth: 232, idealWidth: 268, maxWidth: 308)
                            .hubChromeMaterial()
                    }
                }
            }
            .padding(.top, HubShellLayout.titleBarHeight)

            HubShellTitleBarControls(session: shellSession)
        }
        .ignoresSafeArea(edges: .top)
        .background(HubWindowChromeConfigurator(windowTitle: mainWindowTitle))
        .frame(minWidth: minWindowWidth, minHeight: 720)
        .hubOpensMainWindowFromDock()
        .onAppear {
            // Drain any pending router state that was set while the window was absent
            // (closed-window case). The menu bar action may fire router.execute() before
            // openWindow() recreates this view; onChange only fires on transitions AFTER
            // subscription, so state set before appearance would be silently dropped.
            if let toolID = router.selectedToolID {
                selectTool(toolID)
                router.clearSelectedToolID()
            }
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
        .onChange(of: selectedToolID) { _, newID in
            guard let newID else { return }
            toolPaneCache.ensureMounted(newID)
        }
        .onChange(of: router.selectedToolID) { _, newID in
            if let newID {
                selectTool(newID)
                router.clearSelectedToolID()  // reset so the same ID fires again next time
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .hubOpenSettingsHelpers)) { _ in
            router.openSettingsHelpers()
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
        HubMainWindowTitle.resolved(selectedToolID: shellSession.selectedToolID, registry: registry)
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
        if shellSession.inboxEffectiveVisible { width += 232 }
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

    /// Sidebar writes go through `selectTool` so Settings opens the Settings
    /// window instead of replacing the main pane.
    private var sidebarSelectedToolID: Binding<ToolFeatureID?> {
        Binding(
            get: { selectedToolID },
            set: { newValue in
                guard let newValue else {
                    selectedToolID = nil
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
        toolPaneCache.ensureMounted(toolID)
        selectedToolID = toolID
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
                    ForEach(toolPaneCache.mountedIDs, id: \.self) { toolID in
                        if let toolView = toolPaneCache.view(for: toolID) {
                            toolView
                                .opacity(selectedToolID == toolID ? 1 : 0)
                                .allowsHitTesting(selectedToolID == toolID)
                                .accessibilityHidden(selectedToolID != toolID)
                                .zIndex(selectedToolID == toolID ? 1 : 0)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
