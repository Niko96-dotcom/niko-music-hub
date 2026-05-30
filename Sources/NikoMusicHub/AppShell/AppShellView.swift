import AppCore
import SwiftUI

struct AppShellView: View {
    private static let showToolSidebarKey = "hub.shell.showToolSidebar"
    private static let showOutputInboxKey = "hub.shell.showOutputInbox"

    let registry: ToolRegistry
    let context: ToolContext

    @State private var selectedToolID: ToolFeatureID?
    @AppStorage(Self.showToolSidebarKey) private var showToolSidebar = true
    @AppStorage(Self.showOutputInboxKey) private var showOutputInbox = true

    init(registry: ToolRegistry, context: ToolContext) {
        self.registry = registry
        self.context = context
        _selectedToolID = State(initialValue: registry.preferredDefaultFeatureID)
    }

    var body: some View {
        HStack(spacing: 0) {
            if showToolSidebar {
                ToolSidebarView(
                    context: context,
                    registry: registry,
                    selectedToolID: $selectedToolID
                )
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 270)
                .hubGlassChrome()

                Divider()
            } else {
                collapsedRail(
                    systemImage: "sidebar.left",
                    accessibilityLabel: "Show tools sidebar"
                ) {
                    showToolSidebar = true
                }
            }

            activeToolView
                .frame(minWidth: 660, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
                .toolbar { shellToolbar }

            if showOutputInbox {
                Divider()

                OutputInboxInspectorView(context: context)
                    .frame(minWidth: 300, idealWidth: 320, maxWidth: 380)
                    .hubGlassChrome()
            } else {
                collapsedRail(
                    systemImage: "sidebar.right",
                    accessibilityLabel: "Show output inbox"
                ) {
                    showOutputInbox = true
                }
            }
        }
        .padding(14)
        .frame(minWidth: minWindowWidth, minHeight: 720)
    }

    private var minWindowWidth: CGFloat {
        var width: CGFloat = 720
        if showToolSidebar { width += 220 }
        if showOutputInbox { width += 300 }
        return width
    }

    @ToolbarContentBuilder
    private var shellToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                showToolSidebar.toggle()
            } label: {
                Label(
                    showToolSidebar ? "Hide Tools" : "Show Tools",
                    systemImage: "sidebar.left"
                )
            }
            .help(showToolSidebar ? "Hide tools sidebar" : "Show tools sidebar")

            Button {
                showOutputInbox.toggle()
            } label: {
                Label(
                    showOutputInbox ? "Hide Output Inbox" : "Show Output Inbox",
                    systemImage: "sidebar.right"
                )
            }
            .help(showOutputInbox ? "Hide output inbox" : "Show output inbox")
        }
    }

    private func collapsedRail(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxHeight: .infinity)
                .frame(width: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .hubGlassChrome()
    }

    @ViewBuilder
    private var activeToolView: some View {
        if let selectedToolID,
           let feature = registry.features.first(where: { $0.metadata.id == selectedToolID }) {
            feature.makeView(context: context)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("No tools registered")
                    .font(.system(size: 22, weight: .semibold))
                Text("Register a ToolFeature in the composition root.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
    }
}
