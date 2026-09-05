import AppCore
import NikoMusicCore
import SwiftUI

/// A song row keeps identity, context, and preview controls in a consistent order.
struct SongCardView: View {
    let song: Song
    let isSelected: Bool
    var matchSummary: String?
    var onSelect: (() -> Void)?
    var onWorkflowStatusChange: ((ProjectWorkflowStatus?) -> Void)?
    var vaultPresentation: ProjectVaultCardPresentation?
    var onProjectVaultPrimaryAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @ObservedObject private var playbackCoordinator = ArchivePlaybackCoordinator.shared

    private var hasScanWarning: Bool {
        !song.displayScanWarnings().isEmpty
    }

    private var metadataChips: [SongCardMetadataChip] {
        SongCardMetadataChipBuilder.chips(for: song, matchSummary: matchSummary)
    }

    private var isRowPlaying: Bool {
        guard let mainPreviewURL = song.mainPreviewURL else { return false }
        return playbackCoordinator.activeURL == mainPreviewURL
    }

    private var isArchivedProject: Bool {
        vaultPresentation?.state == .archived
    }

    private var allowsWorkflowMutation: Bool {
        ProjectVaultCardWorkflowPolicy.allowsWorkflowMutation(for: vaultPresentation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HStack(spacing: 6) {
                    Text(song.effectiveDisplayTitle)
                        .font(HubDesignSystem.Typography.body().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if allowsWorkflowMutation, let onWorkflowStatusChange {
                    ArchiveWorkflowStatusMenu(
                        status: song.workflowStatus,
                        compact: true,
                        onSelect: onWorkflowStatusChange
                    )
                } else if let status = song.workflowStatus {
                    ArchiveWorkflowStatusPill(status: status, compact: true)
                } else {
                    Text("No Status")
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                }

                if hasScanWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Palette.warning)
                        .help(song.displayScanWarnings().joined(separator: " "))
                }
            }

            if let vaultPresentation, vaultPresentation.state != .active {
                HStack(spacing: 5) {
                    Text(vaultPresentation.state.rawValue)
                        .font(HubDesignSystem.Typography.micro().weight(.semibold))
                        .foregroundStyle(isArchivedProject ? HubDesignSystem.Palette.textSecondary : HubDesignSystem.Palette.accent)
                    Text(vaultPresentation.explanation)
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .lineLimit(1)

                    Spacer(minLength: 3)

                    if [.restoreAndOpen, .retry].contains(vaultPresentation.primaryAction),
                       let onProjectVaultPrimaryAction {
                        Button(action: onProjectVaultPrimaryAction) {
                            Label(
                                vaultPresentation.primaryAction == .retry ? "Retry" : "Get",
                                systemImage: vaultPresentation.primaryAction == .retry
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
                        .help(vaultPresentation.primaryAction == .retry
                            ? "Retry the preserved Project Vault transfer"
                            : "Get a verified local copy and open it in Cubase")
                        .accessibilityLabel(vaultPresentation.primaryAction == .retry
                            ? "Retry Project Vault transfer"
                            : "Get local copy and open in Cubase")
                    }
                }
            }

            SongCardMetadataChipRow(chips: metadataChips)

            ArchiveMiniPlayerView(
                url: song.mainPreviewURL,
                style: .compact,
                showsSlider: isRowPlaying
            )
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
