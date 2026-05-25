import AppCore
import SwiftUI

struct AppShellView: View {
    let registry: ToolRegistry
    let context: ToolContext

    @State private var selectedToolID: ToolFeatureID?

    init(registry: ToolRegistry, context: ToolContext) {
        self.registry = registry
        self.context = context
        _selectedToolID = State(initialValue: registry.feature(for: "archive-browser")?.metadata.id ?? registry.feature(for: "wav-converter")?.metadata.id ?? registry.features.first?.metadata.id)
    }

    var body: some View {
        HStack(spacing: 0) {
            ToolSidebarView(
                context: context,
                registry: registry,
                selectedToolID: $selectedToolID
            )
            .frame(width: 280)

            Divider()

            activeToolView
                .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            Divider()

            OutputInboxInspectorView(context: context)
                .frame(width: 280)
        }
        .frame(minWidth: 1_060, minHeight: 600)
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
