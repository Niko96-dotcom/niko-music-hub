import AppCore
import SwiftUI

struct AppShellView: View {
    private static let showToolSidebarKey = "hub.shell.panels.toolsVisible"
    private static let showOutputInboxKey = "hub.shell.panels.inboxVisible"
    private static let activeToolMinWidth: CGFloat = 540

    let registry: ToolRegistry
    let context: ToolContext
    @ObservedObject var router: QuickAccessRouter

    @State private var selectedToolID: ToolFeatureID?
    @State private var showToolSidebar: Bool
    @State private var showOutputInbox: Bool

    init(registry: ToolRegistry, context: ToolContext, router: QuickAccessRouter) {
        self.registry = registry
        self.context = context
        self.router = router
        let initialToolID = ToolRegistry.initialToolID()
            .flatMap { registry.feature(for: $0)?.metadata.id }
            ?? registry.preferredDefaultFeatureID
        _selectedToolID = State(initialValue: initialToolID)
        _showToolSidebar = State(initialValue: context.preferences.bool(forKey: Self.showToolSidebarKey) ?? true)
        _showOutputInbox = State(initialValue: context.preferences.bool(forKey: Self.showOutputInboxKey) ?? true)
    }

    var body: some View {
        VStack(spacing: HubDesignSystem.Spacing.shell) {
            persistenceIssueBanner

            HStack(spacing: HubDesignSystem.Spacing.shell) {
                if showToolSidebar {
                    ToolSidebarView(
                        context: context,
                        registry: registry,
                        selectedToolID: $selectedToolID
                    )
                    .frame(minWidth: 190, idealWidth: 220, maxWidth: 250)
                    .hubLiquidPanel(cornerRadius: HubDesignSystem.Radius.shell)
                    .clipShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.shell, style: .continuous))
                } else {
                    CollapsedSidebarRail(
                        systemImage: "sidebar.left",
                        accessibilityLabel: "Show tools sidebar"
                    ) {
                        setToolSidebarVisible(true)
                    }
                }

                activeToolView
                    .frame(minWidth: Self.activeToolMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .layoutPriority(1)
                    .hubLiquidPanel(cornerRadius: HubDesignSystem.Radius.shell)
                    .clipShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.shell, style: .continuous))

                if showOutputInbox {
                    OutputInboxInspectorView(context: context)
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
                        .hubLiquidPanel(cornerRadius: HubDesignSystem.Radius.shell)
                        .clipShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.shell, style: .continuous))
                } else {
                    CollapsedSidebarRail(
                        systemImage: "sidebar.right",
                        accessibilityLabel: "Show output inbox"
                    ) {
                        setOutputInboxVisible(true)
                    }
                }
            }
            .hubGlassGroup(spacing: HubDesignSystem.Spacing.shell)
        }
        .padding(HubDesignSystem.Spacing.shell)
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
        .background(HubShellBackground())
    }

    private var minWindowWidth: CGFloat {
        var width: CGFloat = Self.activeToolMinWidth
        if showToolSidebar { width += 190 }
        if showOutputInbox { width += 220 }
        return width
    }

    @ToolbarContentBuilder
    private var shellToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                setToolSidebarVisible(!showToolSidebar)
            } label: {
                Image(systemName: "sidebar.left")
                    .symbolRenderingMode(.hierarchical)
            }
            .help(showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar")
            .accessibilityLabel(showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar")

            Button {
                setOutputInboxVisible(!showOutputInbox)
            } label: {
                Image(systemName: "sidebar.right")
                    .symbolRenderingMode(.hierarchical)
            }
            .help(showOutputInbox ? "Hide output inbox" : "Show output inbox")
            .accessibilityLabel(showOutputInbox ? "Hide output inbox" : "Show output inbox")
        }
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
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .hubLiquidCard(cornerRadius: HubDesignSystem.Radius.row, intent: .warning)
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
        .toolbar { shellToolbar }
    }
}

private struct CollapsedSidebarRail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(maxHeight: .infinity)
                .frame(width: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .foregroundStyle(isHovered ? HubDesignSystem.Colors.accent : Color.primary)
        .onHover(perform: updateHover)
        .hubLiquidPanel(
            cornerRadius: HubDesignSystem.Radius.shell,
            intent: isHovered ? .hover : .normal,
            interactive: true
        )
    }

    private func updateHover(_ hovering: Bool) {
        if reduceMotion {
            isHovered = hovering
        } else {
            withAnimation(.easeInOut(duration: HubDesignSystem.Liquid.Motion.duration(reduceMotion: reduceMotion))) {
                isHovered = hovering
            }
        }
    }
}
