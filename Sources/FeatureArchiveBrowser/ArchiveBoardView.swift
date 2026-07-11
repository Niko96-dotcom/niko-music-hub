import AppCore
import NikoMusicCore
import SwiftUI

/// Kanban board over the current browse list: one column per workflow stage,
/// drag a card onto a column to change its status (recorded in status history).
struct ArchiveBoardView: View {
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    private var columns: [ArchiveBoardColumn] {
        ArchiveBoardProjection.columns(from: viewModel.filteredSongs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(columns) { column in
                        ArchiveBoardColumnView(column: column, viewModel: viewModel)
                    }
                }
                .padding(.vertical, 2)
            }
            .padding(.top, 14)

            if let song = viewModel.selectedSong {
                ArchiveBoardPlayerBar(song: song, viewModel: viewModel)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: HubDesignSystem.Spacing.controlGap) {
            Text("Board")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                .layoutPriority(1)

            Text("Drag between stages · click to preview · double-click to open")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 8)

            searchField
                .frame(maxWidth: 240)

            HubIconButton(
                systemImage: "sidebar.leading",
                accessibilityLabel: "Back to list",
                help: "Back to the song list (Esc)"
            ) {
                viewModel.showBoard = false
            }
        }
        .frame(minHeight: HubToolLayout.headerMinHeight, alignment: .top)
    }

    /// Same quiet inset search style as the sidebar — the sidebar is hidden
    /// while the board owns the page, so search must live here too.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            TextField("", text: Binding(
                get: { viewModel.searchQuery },
                set: { viewModel.setSearchQuery($0) }
            ), prompt: Text("Search songs").foregroundColor(HubDesignSystem.Palette.textTertiary))
            .textFieldStyle(.plain)
            .font(HubDesignSystem.Typography.body())
            .foregroundStyle(HubDesignSystem.Palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .hubSurface(.field, cornerRadius: HubDesignSystem.Radius.row)
    }
}

private struct ArchiveBoardColumnView: View {
    let column: ArchiveBoardColumn
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            columnHeader

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(column.songs, id: \.id) { song in
                        ArchiveBoardCardView(
                            song: song,
                            isSelected: viewModel.selectedSong?.id == song.id,
                            onSelect: { viewModel.selectSongOnBoard(song) },
                            onOpenDetail: { viewModel.selectSong(song) }
                        )
                        .draggable(song.id)
                    }
                }
            }

            if column.songs.isEmpty {
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(width: 200)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(isDropTargeted ? HubDesignSystem.Palette.accentFill : Color.white.opacity(0.03))
        }
        .dropDestination(for: String.self) { songIDs, _ in
            var moved = false
            for songID in songIDs {
                guard let song = viewModel.songs.first(where: { $0.id == songID }),
                      song.workflowStatus != column.status else { continue }
                viewModel.updateWorkflowStatus(for: song, status: column.status)
                moved = true
            }
            return moved
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title) column, \(column.songs.count) songs")
    }

    private var columnHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: column.status?.archiveSymbolName ?? "tray")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(column.status?.archiveTint ?? HubDesignSystem.Palette.textTertiary)
            Text(column.title)
                .font(HubDesignSystem.Typography.caption().weight(.semibold))
                .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text("\(column.songs.count)")
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
        }
        .padding(.horizontal, 2)
    }
}

private struct ArchiveBoardCardView: View {
    let song: Song
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenDetail: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(song.effectiveDisplayTitle)
                    .font(HubDesignSystem.Typography.bodySmall().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if !song.displayScanWarnings().isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(HubDesignSystem.Palette.warning)
                }
            }

            Text(captionLine)
                .font(HubDesignSystem.Typography.micro())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                .lineLimit(1)

            if let status = song.workflowStatus {
                SongCardStageProgressBar(status: status)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(cardFill)
        }
        .contentShape(Rectangle())
        // Double-click before single so both register: first click selects
        // (loads the player bar), the second opens detail.
        .onTapGesture(count: 2, perform: onOpenDetail)
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.14)) {
                isHovered = hovering
            }
        }
        .help("Click to preview \(song.effectiveDisplayTitle) — double-click to open, drag to change stage")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(song.effectiveDisplayTitle)
    }

    private var captionLine: String {
        var parts: [String] = []
        if let latest = ArchiveShelfRanker.latestCPRActivity(for: song) {
            parts.append(Self.dayFormatter.string(from: latest))
        }
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
        return isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.05)
    }
}

/// Persistent transport at the bottom of the board: the selected card's
/// preview player plus a jump into song detail — audition without leaving
/// the board.
private struct ArchiveBoardPlayerBar: View {
    let song: Song
    @ObservedObject var viewModel: ArchiveBrowserViewModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.effectiveDisplayTitle)
                    .font(HubDesignSystem.Typography.body().weight(.semibold))
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
                    .lineLimit(1)
                if let status = song.workflowStatus {
                    ArchiveWorkflowStatusPill(status: status, compact: true)
                }
            }
            .frame(minWidth: 120, maxWidth: 260, alignment: .leading)

            if mainPreviewURL != nil {
                ArchiveMiniPlayerView(url: mainPreviewURL, style: .full, showsSlider: true)
                    .frame(maxWidth: .infinity)
            } else {
                Text("No preview file for this song")
                    .font(HubDesignSystem.Typography.caption())
                    .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HubIconButton(
                systemImage: "info.circle",
                accessibilityLabel: "Open song detail",
                help: "Open \(song.effectiveDisplayTitle) in song detail"
            ) {
                viewModel.selectSong(song)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubCard(cornerRadius: HubDesignSystem.Radius.row)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board player, \(song.effectiveDisplayTitle)")
    }

    private var mainPreviewURL: URL? {
        guard let id = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == id }) else {
            return nil
        }
        return candidate.filePath
    }
}
