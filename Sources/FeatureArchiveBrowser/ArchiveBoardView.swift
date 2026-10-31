import AppCore
import Foundation
import NikoMusicCore
import ProjectVaultRuntime
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

            if viewModel.library.showsArchiveAccessRecovery {
                EmptyView()
            } else if viewModel.songs.isEmpty {
                ArchiveBoardEmptyState(
                    isScanning: viewModel.library.isScanning,
                    onChooseRoot: onChooseRoot,
                    onOpenListView: { viewModel.setBrowseLayout(list: true) }
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
            guard viewModel.page.showsBoardPage else { return }
            keyboardFocus = .search
        }
        // Selection publishes on the same view model but never emits on this
        // property publisher, so it cannot trigger a full board re-projection.
        .onReceive(viewModel.browse.$filteredSongs) { songs in
            projectionCache.refresh(with: songs, preservingOrder: viewModel.browse.isSearching)
        }
    }

    private var header: some View {
        HubPageHeader("Board") {
            if viewModel.library.isScanning {
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
                input: viewModel.browse.searchInput,
                onEdit: { query in handleSearchEdit(query) },
                isDisabled: viewModel.songs.isEmpty,
                keyboardFocus: $keyboardFocus
            )
            .frame(maxWidth: 240)

            if viewModel.canBrowseArchivedProjects {
                HubIconButton(
                    systemImage: "archivebox",
                    accessibilityLabel: viewModel.vaultObservation.showsArchivedProjects ? "Hide archived songs" : "Show archived songs",
                    help: viewModel.vaultObservation.showsArchivedProjects
                        ? "Hide archived songs"
                        : "Show \(viewModel.archivedProjectCount) archived \(CountCopy.noun(for: viewModel.archivedProjectCount, "song"))",
                    isSelected: viewModel.vaultObservation.showsArchivedProjects,
                    isToggle: true
                ) {
                    viewModel.setShowArchivedProjects(!viewModel.vaultObservation.showsArchivedProjects)
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
            viewModel.browse.clearSearch()
        } else {
            viewModel.browse.setSearchQuery(query)
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
    @ObservedObject var session: ArchivePreviewSession
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
    var scrollActivity: ArchiveBoardScrollActivity? = nil

    @State private var isHovered = false

    private var allowsWorkflowMutation: Bool {
        vaultPresentation?.allowsWorkflowMutation ?? true
    }

    /// Board songs are rows, not cards: the selected row takes the full
    /// selection pill, the row under the pointer half of it (the sidebar's
    /// rule). The lane draws the hairlines between rows.
    private var rowFillOpacity: Double { isSelected ? 1 : isHovered ? 0.5 : 0 }

    /// The play glyph shows on the row under the pointer, the selected row and
    /// the song the preview holds. Elsewhere the button keeps its place and its
    /// accessibility element; only the glyph is hidden.
    private var showsPlayGlyph: Bool { isHovered || isSelected || session.songID == song.id }

    /// Leading text inset of a row; the lane's hairlines start here too.
    static let rowInset: CGFloat = 10
    static let rowPadding = EdgeInsets(top: 4, leading: rowInset, bottom: 4, trailing: 4)
    static let playTarget: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ArchiveBoardRowText(song: song)
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
                        isEnabled: !session.captureActive,
                        size: Self.playTarget,
                        showsGlyph: showsPlayGlyph,
                        hoverTarget: .play(songID: song.id, laneID: song.workflowStatus?.rawValue),
                        scrollActivity: scrollActivity
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
        .padding(Self.rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(HubDesignSystem.Palette.selection.opacity(rowFillOpacity))
                // The hairline under this row stays outside the pill.
                .padding(.bottom, 1)
                .animation(reduceMotion || scrollActivity?.isScrolling == true ? nil : ArchiveBoardMotion.hover,
                           value: rowFillOpacity)
        }
        .contentShape(Rectangle())
        // The title area owns double-click; transport clicks must never open detail.
        .onTapGesture {
            performInteraction(.singleClick)
        }
        .onHover {
            ArchiveBoardScrollActivity.updateHover($0, target: .card(songID: song.id, laneID: song.workflowStatus?.rawValue),
                                                   isHovered: $isHovered, activity: scrollActivity)
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
        .modifier(ArchiveBoardCardDragModifier(song: song, isEnabled: allowsWorkflowMutation))
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
        onPlay?()
    }
}

/// What a board row says: the song's title, nothing else (versions and stems
/// are on the song's page). The row and its drag image both draw it, so the
/// image you drag is the row you see.
struct ArchiveBoardRowText: View {
    let song: Song

    var body: some View {
        Text(song.effectiveDisplayTitle)
            .font(HubDesignSystem.Typography.bodySmall().weight(.medium))
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
}

private struct ArchiveBoardCardDragModifier: ViewModifier {
    let song: Song
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(song.id) {
                ArchiveBoardDragPreview(song: song)
            }
        } else {
            content
        }
    }
}
