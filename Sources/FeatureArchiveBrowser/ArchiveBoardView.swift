import AppCore
import Foundation
import NikoMusicCore
import SwiftUI

/// Kanban board over the current browse list: one column per workflow stage,
/// drag a card onto a column to change its status (recorded in status history).
struct ArchiveBoardView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    /// Opens the archive-root folder picker (owned by the browser shell).
    let onChooseRoot: () -> Void

    @AppStorage("hub.archive.compactEmptyStages") private var compactEmptyStages = false
    /// Owned by `ArchiveBrowserView` so a board → detail → board round trip
    /// does not re-project every column.
    @ObservedObject var projectionCache: ArchiveBoardProjectionCache
    @FocusState.Binding var keyboardFocus: ArchiveKeyboardFocus?

    /// Reading the cache is constant-time; `ArchiveBoardProjection.columns`
    /// only runs when the filtered-song publisher emits a changed input.
    private var columns: [ArchiveBoardColumn] {
        projectionCache.columns
    }

    init(
        viewModel: ArchiveBrowserViewModel,
        projectionCache: ArchiveBoardProjectionCache,
        onChooseRoot: @escaping () -> Void,
        keyboardFocus: FocusState<ArchiveKeyboardFocus?>.Binding
    ) {
        self.viewModel = viewModel
        self.projectionCache = projectionCache
        self.onChooseRoot = onChooseRoot
        self._keyboardFocus = keyboardFocus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if viewModel.showsArchiveAccessRecovery {
                EmptyView()
            } else if viewModel.songs.isEmpty {
                ArchiveBoardEmptyState(
                    isScanning: viewModel.isScanning,
                    onChooseRoot: onChooseRoot,
                    onOpenListView: { viewModel.viewMode = .list }
                )
                .padding(.top, HubToolLayout.sectionSpacing)
            } else {
                ArchiveBoardLanesView(
                    columns: columns,
                    viewModel: viewModel,
                    compactEmptyStages: compactEmptyStages,
                    onInteract: { claimBoardKeyboardFocus() }
                )
                .padding(.top, HubToolLayout.sectionSpacing)
                .simultaneousGesture(TapGesture().onEnded {
                    // Clicking a card returns keyboard control to the board;
                    // otherwise the AppKit search editor can keep Space as text.
                    claimBoardKeyboardFocus()
                })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .archiveSearchFocusRequested)) { _ in
            keyboardFocus = .search
        }
        // Selection publishes on the same view model but never emits on this
        // property publisher, so it cannot trigger a full board re-projection.
        .onReceive(viewModel.$filteredSongs) { songs in
            projectionCache.refresh(with: songs, preservingOrder: viewModel.isSearching)
        }
    }

    private var header: some View {
        HubPageHeader("Board") {
            if viewModel.isScanning {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Scanning archive…")
                        .font(HubDesignSystem.Typography.caption())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    HubLabeledButton(
                        icon: "xmark",
                        label: CancelCopy.cancelScan,
                        style: .secondary,
                        help: CancelCopy.cancelScan
                    ) {
                        viewModel.cancelScan()
                    }
                }
            }
        } trailing: {
            ArchiveBoardSearchField(
                input: viewModel.searchInput,
                onEdit: { query in handleSearchEdit(query) },
                isDisabled: viewModel.songs.isEmpty,
                keyboardFocus: $keyboardFocus
            )
            .frame(maxWidth: 240)

            if viewModel.canBrowseArchivedProjects {
                HubIconButton(
                    systemImage: "archivebox",
                    accessibilityLabel: viewModel.showArchivedProjects ? "Hide archived songs" : "Show archived songs",
                    help: viewModel.showArchivedProjects
                        ? "Hide archived songs"
                        : "Show \(viewModel.archivedProjectCount) archived \(viewModel.archivedProjectCount == 1 ? "song" : "songs")",
                    isSelected: viewModel.showArchivedProjects,
                    isToggle: true
                ) {
                    viewModel.setShowArchivedProjects(!viewModel.showArchivedProjects)
                }
            }

            HubIconButton(
                systemImage: "folder.badge.plus",
                accessibilityLabel: "Add archive folder",
                help: "Add archive folder"
            ) {
                onChooseRoot()
            }

            // Last trailing slot, mirroring analytics' flip icon — same x both ways.
            HubIconButton(
                systemImage: "chart.bar",
                accessibilityLabel: "Show analytics",
                help: "Analytics",
                isEnabled: !viewModel.songs.isEmpty
            ) {
                viewModel.showAnalytics()
            }
        }
    }

    /// Both card clicks and empty-lane clicks hand keyboard control back to
    /// the board so Space and the arrow keys act on the selection.
    private func claimBoardKeyboardFocus() {
        ArchiveShortcutFocusPolicy.claimArchiveKeyFocus()
        keyboardFocus = .archive
    }

    private func handleSearchEdit(_ query: String) {
        if query.isEmpty {
            viewModel.clearSearch()
        } else {
            viewModel.setSearchQuery(query)
        }
    }
}

/// Roots and scanning live in the list layout's sidebar, so an empty
/// archive points there instead of showing eight bare columns.
struct ArchiveBoardEmptyState: View {
    let isScanning: Bool
    let onChooseRoot: () -> Void
    let onOpenListView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                isScanning ? "Scanning your archive" : "No songs on the board",
                systemImage: isScanning ? "arrow.triangle.2.circlepath" : "music.note.list"
            )
            .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            if isScanning {
                Text("Big folders can take a few minutes. Songs from earlier scans stay visible.")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isScanning {
                HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                    HubLabeledButton(
                        icon: "folder.badge.plus",
                        label: "Add Archive Folder",
                        style: .primary
                    ) {
                        onChooseRoot()
                    }
                    HubLabeledButton(
                        icon: "list.bullet",
                        label: "Open List View",
                        style: .ghost
                    ) {
                        onOpenListView()
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row)
    }
}

struct ArchiveBoardCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let song: Song
    let isSelected: Bool
    let vaultPresentation: ProjectVaultCardPresentation?
    var vaultActivityMessage: String? = nil
    let onSelect: () -> Void
    let onOpenDetail: () -> Void
    let onProjectVaultPrimaryAction: (() -> Void)?
    var onPlay: (() -> Void)?
    var onOpenProject: (() -> Void)? = nil
    var onRevealInFinder: (() -> Void)? = nil
    var canRevealInFinder: Bool = false
    var onWorkflowStatusChange: ((ProjectWorkflowStatus?) -> Void)? = nil

    @ObservedObject private var session = ArchivePreviewSession.shared
    @State private var isHovered = false

    private var allowsWorkflowMutation: Bool {
        ProjectVaultCardWorkflowPolicy.allowsWorkflowMutation(for: vaultPresentation)
    }

    private var captionLine: String {
        var parts: [String] = []
        let versions = song.visibleProjectVersions.count
        if versions > 0 {
            parts.append("\(versions) version\(versions == 1 ? "" : "s")")
        }
        if song.hasStems {
            parts.append("stems")
        }
        return parts.isEmpty ? "No project files" : parts.joined(separator: " · ")
    }

    private var cardFill: Color {
        if isSelected { return HubDesignSystem.Palette.selection }
        return isHovered ? HubDesignSystem.Palette.selection : HubDesignSystem.Palette.surfaceRaised
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(song.effectiveDisplayTitle)
                        .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                        .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(captionLine)
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { performInteraction(.singleClick) }
                .simultaneousGesture(TapGesture(count: 2).onEnded { _ in
                    performInteraction(.doubleClick)
                })
                if !song.displayScanWarnings().isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(HubDesignSystem.Palette.warning)
                        .help(song.displayScanWarnings().joined(separator: " "))
                        .accessibilityHidden(true)
                }
                if song.mainPreviewURL != nil, onPlay != nil {
                    ArchiveCardPlayButton(
                        title: song.effectiveDisplayTitle,
                        isPlaying: session.songID == song.id && session.isPlaying,
                        isLoaded: session.songID == song.id,
                        isEnabled: !session.captureActive
                    ) {
                        playPreview()
                    }
                } else if song.mainPreviewURL == nil {
                    Image(systemName: "speaker.slash").help("No preview")
                }
            }

            if let vaultPresentation, vaultPresentation.state != .active || vaultPresentation.isVerifiedCopy || vaultPresentation.primaryAction == .freeUpSpace || vaultActivityMessage != nil {
                ArchiveBoardCardVaultRow(
                    presentation: vaultPresentation,
                    activityMessage: vaultActivityMessage,
                    onPrimaryAction: onProjectVaultPrimaryAction
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(cardFill)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isHovered)
        }
        .overlay {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .strokeBorder(isSelected ? HubDesignSystem.Palette.accent.opacity(0.55)
                              : HubDesignSystem.Palette.separator.opacity(0.7), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        // The title area owns double-click; transport clicks must never open detail.
        .onTapGesture {
            performInteraction(.singleClick)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            SongItemCommands(
                song: song,
                isPreviewPlaying: session.songID == song.id && session.isPlaying,
                captureActive: session.captureActive,
                canRevealInFinder: canRevealInFinder,
                allowsWorkflowMutation: allowsWorkflowMutation,
                onOpenProject: { onOpenProject?() },
                onPlayPreview: playPreview,
                onRevealInFinder: { onRevealInFinder?() },
                onWorkflowStatusChange: onWorkflowStatusChange
            )
        }
        .modifier(ArchiveBoardCardDragModifier(
            songID: song.id,
            title: song.effectiveDisplayTitle,
            status: song.workflowStatus,
            isEnabled: allowsWorkflowMutation
        ))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(song.effectiveDisplayTitle)
        .accessibilityValue(SongCardAccessibility.warningValue(song: song))
        .accessibilityHint("Press to select. Use Open song detail to view details.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(.default) {
            performInteraction(.accessibilityDefault)
        }
        .accessibilityAction(named: "Open song detail") {
            performInteraction(.accessibilityOpenDetail)
        }
        .modifier(SongWorkflowAccessibilityActions(
            enabled: allowsWorkflowMutation && onWorkflowStatusChange != nil,
            onSelect: { onWorkflowStatusChange?($0) }
        ))
    }

    private func performInteraction(_ activation: ArchiveBoardCardInteractionPolicy.Activation) {
        switch ArchiveBoardCardInteractionPolicy.action(for: activation) {
        case .select:
            onSelect()
        case .openDetail:
            onOpenDetail()
        }
    }

    private func playPreview() {
        if session.songID == song.id {
            session.toggle()
        } else {
            onPlay?()
        }
    }
}

private struct ArchiveBoardCardDragModifier: ViewModifier {
    let songID: String
    let title: String
    let status: ProjectWorkflowStatus?
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(songID) {
                ArchiveBoardDragPreview(title: title, status: status)
            }
        } else {
            content
        }
    }
}
