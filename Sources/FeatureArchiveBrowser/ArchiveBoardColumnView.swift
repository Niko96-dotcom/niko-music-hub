import AppCore
import NikoMusicCore
import SwiftUI

/// One workflow lane: header plus the lazy card list, hosted in an AppKit
/// drop target so a card can be dropped onto the column to change its status.
struct ArchiveBoardColumnView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let column: ArchiveBoardColumn
    @ObservedObject var viewModel: ArchiveBrowserViewModel
    let compactWhenEmpty: Bool
    let onDragLocationChanged: (String, CGFloat) -> Void
    let onDragEnded: () -> Void
    let onInteract: () -> Void

    @State private var isDropTargeted = false
    @State private var dropLayout = ArchiveBoardDropLayout()

    private var isCompact: Bool { compactWhenEmpty && !isDropTargeted }
    private var columnWidth: CGFloat { isCompact ? 56 : 220 }

    var body: some View {
        ArchiveBoardDropHost(
            content: columnContent(column),
            renderKey: ArchiveBoardColumnRenderKey(
                column: column,
                selectedSongID: viewModel.selectedSong?.id,
                vaultPresentations: viewModel.projectVaultPresentationsBySongID,
                vaultActivity: viewModel.projectVaultActivityMessages,
                isTargeted: isDropTargeted,
                reduceMotion: reduceMotion,
                colorScheme: colorScheme,
                isCompact: compactWhenEmpty
            ),
            accepts: { acceptsDrop(songID: $0) },
            perform: { performDrop(songID: $0) },
            locationChanged: { onDragLocationChanged(column.id, $0) },
            ended: onDragEnded,
            targeted: { if isDropTargeted != $0 { isDropTargeted = $0 } },
            landingFrame: { dropLayout.frames[$0] },
            // Must return the same opaque type as `content`, so the lookup is
            // a method but the `columnContent` call stays inline.
            refreshedContent: { columnContent(currentColumn()) },
            reduceMotion: reduceMotion
        )
        .frame(width: columnWidth)
        .frame(maxHeight: .infinity)
    }

    private func columnContent(_ column: ArchiveBoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            columnHeader(column)

            ArchiveBoardSongsView(
                songs: column.songs,
                selectedSongID: viewModel.selectedSong.flatMap {
                    $0.workflowStatus == column.status ? $0.id : nil
                },
                vaultPresentations: viewModel.projectVaultPresentationsBySongID,
                vaultActivity: viewModel.projectVaultActivityMessages,
                viewModel: viewModel
            )
            .equatable()

            if column.songs.isEmpty {
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(isDropTargeted ? HubDesignSystem.Palette.accentFill : HubDesignSystem.Palette.surface)
        }
        .environment(\.colorScheme, colorScheme)
        .simultaneousGesture(TapGesture().onEnded(onInteract))
        .coordinateSpace(name: "archive-board-drop-column")
        .onPreferenceChange(ArchiveBoardCardFramesKey.self) { dropLayout.frames = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title) column, \(column.songs.count) songs")
    }

    @ViewBuilder
    private func columnHeader(_ column: ArchiveBoardColumn) -> some View {
        if isCompact {
            VStack(spacing: 12) {
                Image(systemName: column.status?.archiveSymbolName ?? "tray")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(column.status?.archiveTint ?? HubDesignSystem.Palette.textTertiary)
                Text(column.title)
                    .font(HubDesignSystem.Typography.caption().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize()
                    .frame(width: 150, height: 20, alignment: .leading)
                    .rotationEffect(.degrees(90))
                    .frame(width: 20, height: 150)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .help(column.title)
        } else {
            expandedColumnHeader(column)
        }
    }

    private func expandedColumnHeader(_ column: ArchiveBoardColumn) -> some View {
        HStack(spacing: 6) {
            Image(systemName: column.status?.archiveSymbolName ?? "tray")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(column.status?.archiveTint ?? HubDesignSystem.Palette.textTertiary)
            Text(column.title)
                .font(HubDesignSystem.Typography.caption().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            Text("\(column.songs.count)")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private func acceptsDrop(songID: String) -> Bool {
        guard let song = viewModel.songs.first(where: { $0.id == songID }) else { return false }
        return viewModel.canMutateWorkflowStatus(for: song)
    }

    /// Re-check mutability here: `acceptsDrop` ran on drag-enter, and the
    /// Done path below bypasses `applyWorkflowStatus`'s own guard.
    private func performDrop(songID: String) {
        guard let song = viewModel.songs.first(where: { $0.id == songID }),
              viewModel.canMutateWorkflowStatus(for: song),
              song.workflowStatus != column.status else { return }
        if column.status == .done {
            viewModel.requestWorkflowDoneArchive(for: song)
            return
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            viewModel.applyWorkflowStatus(column.status, for: song)
        }
    }

    /// The drop host asks for fresh content after a drop lands; re-project
    /// from the live browse list so the lane reflects the moved card.
    private func currentColumn() -> ArchiveBoardColumn {
        ArchiveBoardProjection.columns(from: viewModel.filteredSongs, preservingOrder: viewModel.isSearching)
            .first(where: { $0.id == column.id }) ?? column
    }
}
