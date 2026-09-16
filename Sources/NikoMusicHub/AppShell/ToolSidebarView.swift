import AppCore
import SwiftUI

/// Labeled navigation sidebar (reference pattern: every tool is an icon + NAME + pill
/// selection row under a muted section header — functions are visible, not hidden behind
/// tooltip-only icons). Chrome stays neutral: monochrome icons, neutral raised-pill
/// selection (never the accent, never system blue — DS-13).
struct ToolSidebarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var context: ToolContext? = nil
    let registry: ToolRegistry
    @Binding var selectedToolID: ToolFeatureID?

    @State private var hoveredToolID: ToolFeatureID?
    @State private var showHelperHealth = false
    @State private var helperHealthHovered = false

    private var appVersionLabel: String {
        AppBuildIdentity().compactLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            appMark

            HubSectionHeader("Library")
            ForEach(registry.metadata.filter { $0.id.rawValue == "archive-browser" }, id: \.id) { metadata in
                toolRow(metadata)
            }

            HubSectionHeader("Production")
                .padding(.top, 16)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(registry.metadata.filter {
                    $0.id.rawValue != "archive-browser" && $0.id.rawValue != "settings"
                }, id: \.id) { metadata in
                    toolRow(metadata)
                }
            }

            Spacer(minLength: 8)

            ForEach(registry.metadata.filter { $0.id.rawValue == "settings" }, id: \.id) { metadata in
                toolRow(metadata)
            }

            if context != nil {
                HubSectionHeader("Status")
                helperHealthRow
                    .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, HubToolLayout.topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: HubDesignSystem.Size.navWidth)
        .onMoveCommand { direction in
            if let next = ToolSidebarSelection.move(
                direction: direction,
                metadata: registry.metadata,
                selectedID: selectedToolID
            ) {
                selectedToolID = next
            }
        }
    }

    private var appMark: some View {
        HStack(spacing: 9) {
            if let logo = HubBrandLogo.sidebar {
                logo
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(HubDesignSystem.Highlight.hairline, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            }
            Text("Niko Music Hub")
                .font(HubDesignSystem.Typography.body().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: HubToolLayout.headerMinHeight, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Niko Music Hub \(appVersionLabel)")
        .help("Niko Music Hub \(appVersionLabel)")
    }

    private func toolRow(_ metadata: ToolMetadata) -> some View {
        Button {
            selectedToolID = metadata.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: metadata.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: isSelected(metadata) ? .semibold : .regular))
                    .frame(width: HubDesignSystem.Size.sidebarIconFrame)

                Text(metadata.displayName)
                    .font(HubDesignSystem.Typography.body().weight(isSelected(metadata) ? .medium : .regular))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: HubDesignSystem.Spacing.navRowHeight)
            .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .hubSidebarNavRow(isSelected: isSelected(metadata))
        .background {
            if isHovered(metadata), !isSelected(metadata) {
                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                    .fill(HubDesignSystem.Palette.selection.opacity(0.5))
            }
        }
        .onHover { hovering in
            updateHover(hovering, toolID: metadata.id)
        }
        .help(metadata.displayName)
        .accessibilityLabel(metadata.displayName)
        .accessibilityValue(ToolSidebarSelection.accessibilityValue(isSelected: isSelected(metadata)))
        .accessibilityAddTraits(ToolSidebarSelection.accessibilityTraits(isSelected: isSelected(metadata)))
        .accessibilityIdentifier("hub_tool_\(metadata.id.rawValue)")
    }

    private var helperHealthRow: some View {
        Button {
            showHelperHealth.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "stethoscope")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: HubDesignSystem.Size.sidebarIconFrame)
                Text("Helper Tools")
                    .font(HubDesignSystem.Typography.body())
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(
                helperHealthHovered
                    ? HubDesignSystem.Palette.textPrimary
                    : HubDesignSystem.Palette.textSecondary
            )
            .padding(.horizontal, 10)
            .frame(height: HubDesignSystem.Spacing.navRowHeight)
            .contentShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            if helperHealthHovered {
                RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                    .fill(HubDesignSystem.Palette.selection.opacity(0.5))
            }
        }
        .onHover { helperHealthHovered = $0 }
        .help("Helper tools status")
        .accessibilityLabel("Helper tools status")
        .accessibilityHint("Shows whether yt-dlp, FFmpeg, and demucs-mlx are ready.")
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

    private func updateHover(_ hovering: Bool, toolID: ToolFeatureID) {
        let nextID: ToolFeatureID? = hovering ? toolID : (hoveredToolID == toolID ? nil : hoveredToolID)
        if reduceMotion {
            hoveredToolID = nextID
        } else {
            withAnimation(.easeInOut(duration: HubDesignSystem.Motion.duration(.short, reduceMotion: reduceMotion))) {
                hoveredToolID = nextID
            }
        }
    }
}
