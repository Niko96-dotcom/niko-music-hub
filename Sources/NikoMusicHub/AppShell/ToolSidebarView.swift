import AppCore
import SwiftUI

struct ToolSidebarView: View {
    var context: ToolContext? = nil
    let registry: ToolRegistry
    @Binding var selectedToolID: ToolFeatureID?

    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let version, !version.isEmpty else { return "" }
        return "v\(version)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if let logo = HubBrandLogo.sidebar {
                    logo
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Niko Music Hub")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if !appVersionLabel.isEmpty {
                        Text(appVersionLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Text("Tools")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(.quaternary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.bottom, 2)

            ForEach(registry.features.map(\.metadata), id: \.id) { metadata in
                Button {
                    selectedToolID = metadata.id
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: metadata.systemImage)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 18, height: 18)
                        Text(metadata.shortLabel)
                            .font(.system(size: 13, weight: isSelected(metadata) ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
                    .padding(.horizontal, 10)
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
                    .padding(10)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func isSelected(_ metadata: ToolMetadata) -> Bool {
        selectedToolID == metadata.id
    }
}
