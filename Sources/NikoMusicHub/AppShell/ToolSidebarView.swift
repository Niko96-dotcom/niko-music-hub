import AppCore
import SwiftUI

struct ToolSidebarView: View {
    var context: ToolContext? = nil
    let registry: ToolRegistry
    @Binding var selectedToolID: ToolFeatureID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let logo = HubBrandLogo.sidebar {
                    logo
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text("Niko Music Hub")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Text("Tools")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            ForEach(registry.features.map(\.metadata), id: \.id) { metadata in
                Button {
                    selectedToolID = metadata.id
                } label: {
                    Label(metadata.shortLabel, systemImage: metadata.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedToolID == metadata.id ? Color.white : Color.primary)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedToolID == metadata.id ? Color.accentColor : Color.clear)
                }
                .accessibilityLabel(metadata.displayName)
            }

            Spacer()

            if let context {
                HelperToolsHealthStrip(context: context)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .hubPanelBackground()
    }
}
