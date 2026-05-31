import AppCore
import SwiftUI

struct AppShellView: View {
    private static let showToolSidebarKey = "hub.shell.panels.toolsVisible"
    private static let showOutputInboxKey = "hub.shell.panels.inboxVisible"

    let registry: ToolRegistry
    let context: ToolContext

    @State private var selectedToolID: ToolFeatureID?
    @AppStorage(Self.showToolSidebarKey) private var showToolSidebar = true
    @AppStorage(Self.showOutputInboxKey) private var showOutputInbox = true

    init(registry: ToolRegistry, context: ToolContext) {
        self.registry = registry
        self.context = context
        let initialToolID = ToolRegistry.initialToolID()
            .flatMap { registry.feature(for: $0)?.metadata.id }
            ?? registry.preferredDefaultFeatureID
        _selectedToolID = State(initialValue: initialToolID)
    }

    var body: some View {
        HStack(spacing: HubDesignSystem.Spacing.shell) {
            if showToolSidebar {
                ToolSidebarView(
                    context: context,
                    registry: registry,
                    selectedToolID: $selectedToolID
                )
                .frame(minWidth: 220, idealWidth: 248, maxWidth: 272)
                .hubGlassPanel(cornerRadius: HubDesignSystem.Radius.shell)
                .clipShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.shell, style: .continuous))
            } else {
                CollapsedSidebarRail(
                    systemImage: "sidebar.left",
                    accessibilityLabel: "Show tools sidebar"
                ) {
                    showToolSidebar = true
                }
            }

            activeToolView
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .layoutPriority(1)
                .hubGlassPanel(cornerRadius: HubDesignSystem.Radius.shell)
                .clipShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.shell, style: .continuous))

            if showOutputInbox {
                OutputInboxInspectorView(context: context)
                    .frame(minWidth: 280, idealWidth: 308, maxWidth: 340)
                    .hubGlassPanel(cornerRadius: HubDesignSystem.Radius.shell)
                    .clipShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.shell, style: .continuous))
            } else {
                CollapsedSidebarRail(
                    systemImage: "sidebar.right",
                    accessibilityLabel: "Show output inbox"
                ) {
                    showOutputInbox = true
                }
            }
        }
        .hubGlassGroup(spacing: HubDesignSystem.Spacing.shell)
        .padding(HubDesignSystem.Spacing.shell)
        .frame(minWidth: minWindowWidth, minHeight: 720)
        .background(HubShellBackground())
    }

    private var minWindowWidth: CGFloat {
        var width: CGFloat = 480
        if showToolSidebar { width += 220 }
        if showOutputInbox { width += 260 }
        return width
    }

    @ToolbarContentBuilder
    private var shellToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                showToolSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .symbolRenderingMode(.hierarchical)
            }
            .help(showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar")
            .accessibilityLabel(showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar")

            Button {
                showOutputInbox.toggle()
            } label: {
                Image(systemName: "sidebar.right")
                    .symbolRenderingMode(.hierarchical)
            }
            .help(showOutputInbox ? "Hide output inbox" : "Show output inbox")
            .accessibilityLabel(showOutputInbox ? "Hide output inbox" : "Show output inbox")
        }
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
            }
        }
        .hubToolContentColumn()
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
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.shell, style: .continuous)
                .fill(isHovered ? HubDesignSystem.Colors.accentTint : Color.clear)
        }
        .onHover(perform: updateHover)
        .hubGlassPanel(cornerRadius: HubDesignSystem.Radius.shell)
    }

    private func updateHover(_ hovering: Bool) {
        if reduceMotion {
            isHovered = hovering
        } else {
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
