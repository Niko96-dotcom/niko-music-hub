import AppCore
import SwiftUI

struct ToolSidebarView: View {
    var context: ToolContext? = nil
    let registry: ToolRegistry
    @Binding var selectedToolID: ToolFeatureID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if let logo = HubBrandLogo.sidebar {
                    logo
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Niko Music Hub")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("Local tools")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Text("Tools")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            ForEach(registry.features.map(\.metadata), id: \.id) { metadata in
                Button {
                    selectedToolID = metadata.id
                } label: {
                    Label(metadata.shortLabel, systemImage: metadata.systemImage)
                        .font(.system(size: 13, weight: isSelected(metadata) ? .semibold : .medium))
                        .symbolRenderingMode(.hierarchical)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hubSidebarNavRow(isSelected: isSelected(metadata))
                .accessibilityLabel(metadata.displayName)
                .accessibilityValue(metadata.shortLabel)
                .accessibilityIdentifier("hub_tool_\(metadata.id.rawValue)")
            }

            Spacer()

            if let context {
                HelperToolsHealthStrip(context: context)
                    .padding(12)
                    .hubGlassCard(cornerRadius: HubDesignSystem.Radius.card)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func isSelected(_ metadata: ToolMetadata) -> Bool {
        selectedToolID == metadata.id
    }
}
