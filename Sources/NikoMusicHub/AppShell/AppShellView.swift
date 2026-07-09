import AppCore
import SwiftUI

struct AppShellView: View {
    private static let showToolSidebarKey = "hub.shell.panels.toolsVisible"
    private static let showOutputInboxKey = "hub.shell.panels.inboxVisible"
    private static let inboxMigrationKey = "hub.shell.migratedInboxDefault.v2"
    private static let activeToolMinWidth: CGFloat = 540
    private static let compactInboxCollapseWidth: CGFloat = 1180

    let registry: ToolRegistry
    let context: ToolContext
    @ObservedObject var router: QuickAccessRouter

    @State private var selectedToolID: ToolFeatureID?
    @State private var showToolSidebar: Bool
    @State private var showOutputInbox: Bool
    @State private var windowWidth: CGFloat = 1400

    init(registry: ToolRegistry, context: ToolContext, router: QuickAccessRouter) {
        self.registry = registry
        self.context = context
        self.router = router
        let initialToolID = ToolRegistry.initialToolID()
            .flatMap { registry.feature(for: $0)?.metadata.id }
            ?? registry.preferredDefaultFeatureID
        _selectedToolID = State(initialValue: initialToolID)
        _showToolSidebar = State(initialValue: context.preferences.bool(forKey: Self.showToolSidebarKey) ?? true)

        let migrated = context.preferences.bool(forKey: Self.inboxMigrationKey) ?? false
        let storedInbox = context.preferences.bool(forKey: Self.showOutputInboxKey)
        let initialInboxVisible: Bool
        if !migrated {
            initialInboxVisible = storedInbox ?? false
            if storedInbox == nil {
                context.preferences.set(false, forKey: Self.showOutputInboxKey)
            }
            context.preferences.set(true, forKey: Self.inboxMigrationKey)
        } else {
            initialInboxVisible = storedInbox ?? false
        }
        _showOutputInbox = State(initialValue: initialInboxVisible)
    }

    var body: some View {
        VStack(spacing: 0) {
            persistenceIssueBanner

            // Flush, edge-to-edge split layout — columns sit shoulder-to-shoulder on an
            // inky canvas, separated by hairline dividers (no floating panels / gaps).
            HStack(spacing: 0) {
                if showToolSidebar {
                    ToolSidebarView(
                        context: context,
                        onCollapse: { setToolSidebarVisible(false) },
                        registry: registry,
                        selectedToolID: $selectedToolID
                    )
                    .frame(width: HubDesignSystem.Size.navWidth)
                    .hubChromeMaterial()
                    shellDivider
                } else {
                    CollapsedSidebarRail(
                        systemImage: "sidebar.left",
                        accessibilityLabel: "Show tools sidebar",
                        topInset: HubShellLayout.toolSidebarControlTopInset
                    ) {
                        setToolSidebarVisible(true)
                    }
                    shellDivider
                }

                activeToolView
                    .frame(minWidth: Self.activeToolMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .layoutPriority(1)
                    .background(HubDesignSystem.Palette.canvas)

                if showOutputInbox {
                    shellDivider
                    OutputInboxInspectorView(
                        context: context,
                        onCollapse: { setOutputInboxVisible(false) }
                    )
                        .padding(.top, 12)
                        .frame(minWidth: 232, idealWidth: 268, maxWidth: 308)
                        .hubChromeMaterial()
                } else {
                    shellDivider
                    CollapsedSidebarRail(
                        systemImage: "sidebar.right",
                        accessibilityLabel: "Show output inbox",
                        topInset: HubShellLayout.outputInboxControlTopInset
                    ) {
                        setOutputInboxVisible(true)
                    }
                }
            }
        }
        .frame(minWidth: minWindowWidth, minHeight: 720)
        .onAppear {
            // Drain any pending router state that was set while the window was absent
            // (closed-window case). The menu bar action may fire router.execute() before
            // openWindow() recreates this view; onChange only fires on transitions AFTER
            // subscription, so state set before appearance would be silently dropped.
            if let toolID = router.selectedToolID {
                selectedToolID = toolID
                router.clearSelectedToolID()
            }
            if router.revealOutputInbox {
                setOutputInboxVisible(true)
                router.clearRevealOutputInbox()
            }
        }
        .onChange(of: router.selectedToolID) { _, newID in
            if let newID {
                selectedToolID = newID
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
            if selectedToolID != ToolFeatureID("wav-converter") {
                selectedToolID = ToolFeatureID("wav-converter")
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { windowWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        windowWidth = width
                        if width < Self.compactInboxCollapseWidth, showOutputInbox {
                            setOutputInboxVisible(false)
                        }
                    }
            }
        }
        .background(HubShellBackground())
    }

    /// Full-height hairline that separates flush columns (the reference split-view seam).
    private var shellDivider: some View {
        HubDesignSystem.Palette.separator
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private var minWindowWidth: CGFloat {
        var width: CGFloat = Self.activeToolMinWidth
        if showToolSidebar { width += HubDesignSystem.Size.navWidth }
        if showOutputInbox { width += 232 }
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

    private func setToolSidebarVisible(_ visible: Bool) {
        showToolSidebar = visible
        context.preferences.set(visible, forKey: Self.showToolSidebarKey)
    }

    private func setOutputInboxVisible(_ visible: Bool) {
        showOutputInbox = visible
        context.preferences.set(visible, forKey: Self.showOutputInboxKey)
    }

    @ViewBuilder
    private var activeToolView: some View {
        Group {
            if let selectedToolID,
               let feature = registry.features.first(where: { $0.metadata.id == selectedToolID }) {
                feature.makeView(context: context)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("No tools registered")
                        .font(HubDesignSystem.Typography.screenTitle())
                    Text("Register a ToolFeature in the composition root.")
                        .font(HubDesignSystem.Typography.body())
                        .foregroundStyle(.secondary)
                }
                .hubToolContentColumn()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct CollapsedSidebarRail: View {
    let systemImage: String
    let accessibilityLabel: String
    let topInset: CGFloat
    let action: () -> Void

    var body: some View {
        // Pin the expand control to the same vertical slot as the expanded sidebar header.
        VStack(spacing: 0) {
            HubIconButton(
                systemImage: systemImage,
                accessibilityLabel: accessibilityLabel,
                action: action
            )
            .padding(.top, topInset)
            Spacer(minLength: 0)
        }
        .frame(width: 32)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
