import AppCore
import SwiftUI

/// Slim left icon rail (Intercom / Analog / Knowledge-Base style): the app mark on top,
/// one icon per registered tool with a leading accent selection indicator + tooltips, and a
/// helper-health button at the bottom. Icon-only keeps the nav compact; discoverability comes
/// from `.help(...)` tooltips and the active tool's own content header (which names the tool).
struct ToolSidebarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var context: ToolContext? = nil
    let registry: ToolRegistry
    @Binding var selectedToolID: ToolFeatureID?

    @State private var hoveredToolID: ToolFeatureID?
    @State private var showHelperHealth = false

    private static let railWidth: CGFloat = 64

    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let version, !version.isEmpty else { return "" }
        return "v\(version)"
    }

    var body: some View {
        VStack(spacing: 6) {
            appMark
                .padding(.top, 34)
                .padding(.bottom, 4)

            HubDesignSystem.Palette.separator
                .frame(width: 26, height: 0.5)
                .padding(.bottom, 2)

            ForEach(registry.features.map(\.metadata), id: \.id) { metadata in
                toolIcon(metadata)
            }

            Spacer(minLength: 8)

            if context != nil {
                helperHealthButton
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(width: Self.railWidth)
    }

    private var appMark: some View {
        Group {
            if let logo = HubBrandLogo.sidebar {
                logo
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(HubDesignSystem.Palette.separator, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            }
        }
        .accessibilityLabel("Niko Music Hub \(appVersionLabel)")
        .help("Niko Music Hub \(appVersionLabel)")
    }

    private func toolIcon(_ metadata: ToolMetadata) -> some View {
        HStack(spacing: 0) {
            // Leading accent bar marks the selected tool (accent = meaningful selection).
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isSelected(metadata) ? HubDesignSystem.Palette.accent : Color.clear)
                .frame(width: 3, height: 22)

            toolRailButton(metadata)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func toolRailButton(_ metadata: ToolMetadata) -> some View {
        if #available(macOS 26.0, *) {
            if isSelected(metadata) {
                Button {
                    selectedToolID = metadata.id
                } label: {
                    toolIconImage(metadata)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .padding(.trailing, 4)
                .onHover { hovering in
                    updateHover(hovering, toolID: metadata.id)
                }
                .help(metadata.displayName)
                .accessibilityLabel(metadata.displayName)
                .accessibilityValue(metadata.shortLabel)
                .accessibilityIdentifier("hub_tool_\(metadata.id.rawValue)")
            } else {
                Button {
                    selectedToolID = metadata.id
                } label: {
                    toolIconImage(metadata)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .padding(.trailing, 4)
                .onHover { hovering in
                    updateHover(hovering, toolID: metadata.id)
                }
                .help(metadata.displayName)
                .accessibilityLabel(metadata.displayName)
                .accessibilityValue(metadata.shortLabel)
                .accessibilityIdentifier("hub_tool_\(metadata.id.rawValue)")
            }
        } else {
            Button {
                selectedToolID = metadata.id
            } label: {
                toolIconImage(metadata)
                    .hubCard(
                        cornerRadius: HubDesignSystem.Radius.row,
                        state: isSelected(metadata) ? .selected : .normal,
                        interactive: true
                    )
                    .padding(.trailing, 4)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                updateHover(hovering, toolID: metadata.id)
            }
            .help(metadata.displayName)
            .accessibilityLabel(metadata.displayName)
            .accessibilityValue(metadata.shortLabel)
            .accessibilityIdentifier("hub_tool_\(metadata.id.rawValue)")
        }
    }

    private func toolIconImage(_ metadata: ToolMetadata) -> some View {
        Image(systemName: metadata.systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 16, weight: isSelected(metadata) ? .semibold : .regular))
            .foregroundStyle(iconForeground(for: metadata))
            .frame(width: 40, height: 38)
            .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
    }

    private var helperHealthButton: some View {
        Button {
            showHelperHealth.toggle()
        } label: {
            Image(systemName: "stethoscope")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Helper tools status")
        .accessibilityLabel("Helper tools status")
        .popover(isPresented: $showHelperHealth, arrowEdge: .leading) {
            if let context {
                HelperToolsHealthStrip(context: context)
                    .frame(width: 240)
                    .padding(12)
            }
        }
    }

    private func isSelected(_ metadata: ToolMetadata) -> Bool {
        selectedToolID == metadata.id
    }

    private func isHovered(_ metadata: ToolMetadata) -> Bool {
        hoveredToolID == metadata.id
    }

    private func iconForeground(for metadata: ToolMetadata) -> Color {
        if isSelected(metadata) {
            return HubDesignSystem.Palette.accent
        }
        return isHovered(metadata)
            ? HubDesignSystem.Palette.textPrimary
            : HubDesignSystem.Palette.textSecondary
    }

    private func updateHover(_ hovering: Bool, toolID: ToolFeatureID) {
        let nextID: ToolFeatureID? = hovering ? toolID : (hoveredToolID == toolID ? nil : hoveredToolID)
        if reduceMotion {
            hoveredToolID = nextID
        } else {
            withAnimation(.easeInOut(duration: HubDesignSystem.Liquid.Motion.duration(reduceMotion: reduceMotion))) {
                hoveredToolID = nextID
            }
        }
    }
}
