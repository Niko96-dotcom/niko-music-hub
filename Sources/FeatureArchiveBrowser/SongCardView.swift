import AppCore
import NikoMusicCore
import SwiftUI

/// A song row keeps identity, context, and preview controls in a consistent order.
struct SongCardView: View {
    let song: Song
    let isSelected: Bool
    var matchSummary: String?
    var onSelect: (() -> Void)?
    var onOpenDetail: (() -> Void)?
    var onPlay: (() -> Void)?
    var onOpenProject: (() -> Void)?
    var onRevealInFinder: (() -> Void)?
    var canRevealInFinder: Bool = false
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
        Button(action: { onSelect?() }) {
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
                    listPlayAffordance
                    if hasScanWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(HubDesignSystem.Palette.warning)
                            .help(song.displayScanWarnings().joined(separator: " "))
                            .accessibilityHidden(true)
                    }
                }
                if let vaultPresentation, vaultPresentation.state != .active || vaultPresentation.isVerifiedCopy || vaultPresentation.primaryAction == .freeUpSpace || vaultActivityMessage != nil {
                    HStack(spacing: 5) {
                        Text(vaultActivityMessage ?? vaultPresentation.statusLabel)
                            .font(HubDesignSystem.Typography.micro().weight(.semibold))
                            .foregroundStyle(isArchivedProject ? HubDesignSystem.Palette.textSecondary : HubDesignSystem.Palette.accent)
                        Text(vaultPresentation.explanation)
                            .font(HubDesignSystem.Typography.micro())
                            .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                            .lineLimit(1)

                        Spacer(minLength: 3)

                        let isRetryAction = vaultPresentation.primaryAction == .retry || (vaultPresentation.retryRestoreID != nil && vaultPresentation.reviewAction == nil)
                        let isFreeUpSpaceAction = vaultPresentation.primaryAction == .freeUpSpace
                        if vaultActivityMessage == nil, ([.restoreAndOpen, .retry, .freeUpSpace].contains(vaultPresentation.primaryAction) || isRetryAction),
                           let onProjectVaultPrimaryAction {
                            Button(action: onProjectVaultPrimaryAction) {
                                Label(
                                    isRetryAction ? "Retry" : (isFreeUpSpaceAction ? vaultPresentation.primaryActionLabel : "Restore"),
                                    systemImage: isRetryAction
                                        ? "arrow.clockwise.circle"
                                        : (isFreeUpSpaceAction ? "trash" : "arrow.down.circle")
                                )
                                    .font(HubDesignSystem.Typography.micro().weight(.semibold))
                                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(HubDesignSystem.Palette.selection, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(isRetryAction || isFreeUpSpaceAction
                                ? vaultPresentation.explanation
                                : "Copies the verified Vault copy back to Active Projects and opens it. The Vault copy stays as it is.")
                            .accessibilityLabel(isRetryAction || isFreeUpSpaceAction
                                ? vaultPresentation.primaryActionLabel
                                : "Restore & Open")
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { _ in
            onOpenDetail?()
        })
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            SongItemCommands(
                song: song,
                isPreviewPlaying: isRowPlaying,
                captureActive: session.captureActive,
                canRevealInFinder: canRevealInFinder,
                allowsWorkflowMutation: allowsWorkflowMutation,
                onOpenProject: { onOpenProject?() },
                onPlayPreview: playPreview,
                onRevealInFinder: { onRevealInFinder?() },
                onWorkflowStatusChange: onWorkflowStatusChange
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SongCardAccessibility.summary(song: song))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Select song") { onSelect?() }
        .accessibilityAction(named: "Open song detail") { onOpenDetail?() }
        .onHover { hovering in
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.14)) {
                isHovered = hovering
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isRowPlaying)
    }

    @ViewBuilder
    private var listPlayAffordance: some View {
        switch SongCardPlayAffordance.kind(
            hasPreview: song.mainPreviewURL != nil,
            captureActive: session.captureActive
        ) {
        case .play(let enabled):
            ArchiveCardPlayButton(
                title: song.effectiveDisplayTitle,
                isPlaying: isRowPlaying,
                isLoaded: isRowLoaded,
                isEnabled: enabled
            ) {
                playPreview()
            }
        case .noPreview:
            Image(systemName: "speaker.slash")
                .help("No preview")
                .accessibilityLabel("No preview")
        case .pausedForCapture:
            ArchiveCardPlayButton(
                title: song.effectiveDisplayTitle,
                isPlaying: isRowPlaying,
                isLoaded: isRowLoaded,
                isEnabled: false
            ) {
                playPreview()
            }
            .help("Preview paused because recording is active.")
            .accessibilityHint("Preview paused because recording is active.")
        }
    }

    private var rowFill: Color {
        if isSelected { return HubDesignSystem.Palette.selection }
        return isHovered ? HubDesignSystem.Palette.surface : Color.clear
    }

    private func playPreview() {
        if isRowLoaded { session.toggle() }
        else if let onPlay { onPlay() }
        else { session.audition(song: song, openSong: { onSelect?() }) }
    }
}
