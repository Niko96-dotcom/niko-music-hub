import AppCore
import NikoMusicCore
import SwiftUI

/// Archive sidebar row — option D: title, metadata chips, minimal inline transport.
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                rowSelectable {
                    HStack(spacing: 6) {
                        Text(song.effectiveDisplayTitle)
                            .font(HubDesignSystem.Typography.body().weight(.semibold))
                            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

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

            if let vaultPresentation {
                HStack(spacing: 5) {
                    Text(vaultPresentation.state.rawValue)
                        .font(HubDesignSystem.Typography.micro().weight(.semibold))
                        .foregroundStyle(isArchivedProject ? HubDesignSystem.Palette.textSecondary : HubDesignSystem.Palette.accent)
                    Text(vaultPresentation.explanation)
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .lineLimit(1)

                    Spacer(minLength: 3)

                    if vaultPresentation.primaryAction == .restoreAndOpen,
                       let onProjectVaultPrimaryAction {
                        Button(action: onProjectVaultPrimaryAction) {
                            Label("Get", systemImage: "arrow.down.circle")
                                .font(HubDesignSystem.Typography.micro().weight(.semibold))
                                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Get a verified local copy and open it in Cubase")
                        .accessibilityLabel("Get local copy and open in Cubase")
                    }
                }
            }

            rowSelectable {
                SongCardMetadataChipRow(chips: metadataChips)
            }

            if let status = song.workflowStatus {
                SongCardStageProgressBar(status: status)
                    .padding(.top, 1)
            }

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
        }
        .opacity(isArchivedProject ? 0.68 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.14)) {
                isHovered = hovering
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isRowPlaying)
    }

    @ViewBuilder
    private func rowSelectable<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect?()
            }
    }

    private var rowFill: Color {
        if isSelected { return HubDesignSystem.Palette.selection }
        return isHovered ? Color.white.opacity(0.05) : Color.clear
    }
}
