import AppCore
import NikoMusicCore
import SwiftUI

/// A song row keeps identity, context, and preview controls in a consistent order.
struct SongCardView: View {
    let song: Song
    let isSelected: Bool
    var matchSummary: String?
    var onSelect: (() -> Void)?
    var onPlay: (() -> Void)?
    var onWorkflowStatusChange: ((ProjectWorkflowStatus?) -> Void)?
    var vaultPresentation: ProjectVaultCardPresentation?
    var vaultActivityMessage: String? = nil
    var onProjectVaultPrimaryAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @ObservedObject private var session = ArchivePreviewSession.shared

    private var hasScanWarning: Bool {
        !song.displayScanWarnings().isEmpty
    }

    private var isRowLoaded: Bool { session.songID == song.id }
    private var isRowPlaying: Bool { isRowLoaded && session.isPlaying }

    private var isArchivedProject: Bool {
        vaultPresentation?.state == .archived
    }

    private var allowsWorkflowMutation: Bool {
        ProjectVaultCardWorkflowPolicy.allowsWorkflowMutation(for: vaultPresentation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.effectiveDisplayTitle)
                        .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        Text("\(song.workflowStatus?.displayTitle ?? "No Status") · \(song.visibleProjectVersions.count) version\(song.visibleProjectVersions.count == 1 ? "" : "s")")
                            .font(HubDesignSystem.Typography.micro()).foregroundStyle(.secondary)
                        if isRowLoaded {
                            Text(isRowPlaying ? "Playing" : "In player")
                                .font(HubDesignSystem.Typography.micro()).foregroundStyle(HubDesignSystem.Palette.accent)
                        }
                    }
                    if let matchSummary, !matchSummary.isEmpty {
                        Text(matchSummary).font(HubDesignSystem.Typography.micro())
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ArchiveCardPlayButton(
                    title: song.effectiveDisplayTitle,
                    isPlaying: isRowPlaying,
                    isLoaded: isRowLoaded,
                    isEnabled: song.mainPreviewURL != nil && !session.captureActive
                ) {
                    if isRowLoaded { session.toggle() }
                    else if let onPlay { onPlay() }
                    else { session.audition(song: song, openSong: { onSelect?() }) }
                }
                if hasScanWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(HubDesignSystem.Palette.warning)
                        .help(song.displayScanWarnings().joined(separator: " "))
                }
            }
            if let vaultPresentation, vaultPresentation.state != .active || vaultActivityMessage != nil {
                HStack(spacing: 5) {
                    Text(vaultActivityMessage ?? vaultPresentation.statusLabel)
                        .font(HubDesignSystem.Typography.micro().weight(.semibold))
                        .foregroundStyle(isArchivedProject ? HubDesignSystem.Palette.textSecondary : HubDesignSystem.Palette.accent)
                    Text(vaultPresentation.explanation)
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .lineLimit(1)

                    Spacer(minLength: 3)

                    if vaultActivityMessage == nil, ([.restoreAndOpen, .retry].contains(vaultPresentation.primaryAction) || (vaultPresentation.retryRestoreID != nil && vaultPresentation.reviewAction == nil)),
                       let onProjectVaultPrimaryAction {
                        Button(action: onProjectVaultPrimaryAction) {
                            Label(
                                (vaultPresentation.primaryAction == .retry || (vaultPresentation.retryRestoreID != nil && vaultPresentation.reviewAction == nil)) ? "Retry" : "Get",
                                systemImage: (vaultPresentation.primaryAction == .retry || (vaultPresentation.retryRestoreID != nil && vaultPresentation.reviewAction == nil))
                                    ? "arrow.clockwise.circle"
                                    : "arrow.down.circle"
                            )
                                .font(HubDesignSystem.Typography.micro().weight(.semibold))
                                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(HubDesignSystem.Palette.selection, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help((vaultPresentation.primaryAction == .retry || (vaultPresentation.retryRestoreID != nil && vaultPresentation.reviewAction == nil))
                            ? vaultPresentation.explanation
                            : "Restore a verified copy into Active Projects and open it in its DAW. The archive copy stays intact.")
                        .accessibilityLabel((vaultPresentation.primaryAction == .retry || (vaultPresentation.retryRestoreID != nil && vaultPresentation.reviewAction == nil))
                            ? vaultPresentation.primaryActionLabel
                            : "Restore local copy and open project")
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(rowFill)
                .overlay {
                    RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                        .strokeBorder(isSelected ? HubDesignSystem.Palette.selectionStroke : .clear, lineWidth: 1)
                }
        }
        // Select from the entire row, including padding and the space beside
        // transport. Child buttons retain their own actions.
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
        .contextMenu {
            if allowsWorkflowMutation, let onWorkflowStatusChange {
                Button("No Status") { onWorkflowStatusChange(nil) }
                ForEach(ProjectWorkflowStatus.allCases, id: \.self) { status in
                    Button(status.displayTitle) { onWorkflowStatusChange(status) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(song.effectiveDisplayTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Select song") { onSelect?() }
        .onHover { hovering in
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.14)) {
                isHovered = hovering
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isRowPlaying)
    }

    private var rowFill: Color {
        if isSelected { return HubDesignSystem.Palette.selection }
        return isHovered ? HubDesignSystem.Palette.surface : Color.clear
    }
}
