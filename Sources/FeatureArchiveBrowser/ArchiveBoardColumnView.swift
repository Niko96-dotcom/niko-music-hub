import AppCore
import AppKit
import NikoMusicCore
import ProjectVaultRuntime
import SwiftUI

/// Value inputs for one retained native lane. The model is used for actions;
/// the parent supplies presentation values through one observation boundary.
struct ArchiveBoardColumnInput {
    let column: ArchiveBoardColumn
    let state: ArchiveBoardLaneState
    let viewModel: ArchiveBrowserViewModel
    let compactWhenEmpty: Bool
    let colorScheme: ColorScheme
    let reduceMotion: Bool
    let boardScroll: ArchiveBoardScrollController
    let locationChanged: (String, CGFloat) -> Void
    let ended: () -> Void
}

@MainActor
final class ArchiveBoardNativeColumn {
    let view: ArchiveBoardDropHostingView<ArchiveBoardColumnContent>
    private var input: ArchiveBoardColumnInput
    private let dropLayout = ArchiveBoardDropLayout()
    private var isTargeted = false

    var width: CGFloat {
        input.compactWhenEmpty && !isTargeted ? ArchiveBoardLaneLayout.compactWidth : ArchiveBoardLaneLayout.expandedWidth
    }

    init(input: ArchiveBoardColumnInput) {
        self.input = input
        view = ArchiveBoardDropHostingView(rootView: Self.content(input: input, column: input.column,
                                                                 state: input.state, targeted: false, layout: dropLayout))
        apply(input)
    }

    func apply(_ next: ArchiveBoardColumnInput) {
        let ownerChanged = input.viewModel !== next.viewModel || input.boardScroll !== next.boardScroll
        input = next
        let content = Self.content(input: input, column: input.column, state: input.state,
                                   targeted: isTargeted, layout: dropLayout)
        if ownerChanged { view.renderedKey = nil }
        ArchiveBoardDropHost(
            content: content,
            renderKey: ArchiveBoardColumnRenderKey(
                column: input.column, selectedSongID: input.state.selectedSong?.id,
                vaultPresentations: input.state.vaultPresentations, vaultActivity: input.state.vaultActivity,
                isTargeted: isTargeted, reduceMotion: input.reduceMotion, colorScheme: input.colorScheme,
                isCompact: input.compactWhenEmpty, isBoardVisible: input.state.isBoardVisible
            ),
            accepts: { [weak self] in self?.acceptsDrop(songID: $0) == true },
            perform: { [weak self] in self?.performDrop(songID: $0, at: $1) ?? false },
            locationChanged: { [weak self] x in
                guard let self else { return }
                self.input.locationChanged(self.input.column.id, x)
            },
            pointerChanged: { [weak self] in self?.showDropPlace(for: $0) },
            ended: { [weak self] in self?.input.ended() },
            targeted: { [weak self] in self?.setTargeted($0) },
            land: { [weak self] in self?.revealDrop(songID: $0) },
            refreshedContent: { [weak self] in
                guard let self else { return content }
                let column = ArchiveBoardProjection.columns(from: self.input.viewModel.browse.filteredSongs,
                                                             preservingOrder: self.input.viewModel.browse.isSearching)
                    .first { $0.id == self.input.column.id } ?? self.input.column
                return Self.content(input: self.input, column: column,
                                    state: ArchiveBoardLaneState(viewModel: self.input.viewModel),
                                    targeted: self.isTargeted, layout: self.dropLayout)
            },
            boardScroll: input.boardScroll
        ).update(view)
    }

    private func setTargeted(_ targeted: Bool) {
        guard targeted != isTargeted else { return }
        isTargeted = targeted
        apply(input)
        input.boardScroll.scrollView?.layoutSubtreeIfNeeded()
    }

    private func acceptsDrop(songID: String) -> Bool {
        guard let song = input.viewModel.songs.first(where: { $0.id == songID }) else { return false }
        return input.viewModel.canMutateWorkflowStatus(for: song)
    }

    /// False when the drop moves nothing (the song's own place, a song that
    /// cannot move now), so AppKit slides the image back.
    private func performDrop(songID: String, at windowPoint: NSPoint) -> Bool {
        guard let song = input.viewModel.songs.first(where: { $0.id == songID }),
              input.viewModel.canMutateWorkflowStatus(for: song) else { return false }
        let place = dropPlace(of: song, at: windowPoint)
        let sameLane = song.workflowStatus == input.column.status
        if sameLane, place == nil { return false }
        if input.column.status == .done, !sameLane {
            input.viewModel.requestWorkflowDoneArchive(for: song)
            return true
        }
        let position = place.map { ArchiveBoardProjection.position(insertingAt: $0.index, in: $0.lane) }
        withAnimation(input.reduceMotion ? nil : ArchiveBoardMotion.moveAnimation) {
            input.viewModel.applyWorkflowStatus(input.column.status, for: song, boardPosition: position)
        }
        return true
    }

    /// Where a drop at `windowPoint` places `song`: the index among this lane's
    /// songs without it. Nil when the lane takes no place (a search keeps its
    /// relevance order; a drop into Done waits for its confirmation) or the
    /// place is the song's own.
    private func dropPlace(of song: Song, at windowPoint: NSPoint) -> (index: Int, lane: [Song])? {
        guard !input.viewModel.browse.isSearching,
              input.column.status != .done || song.workflowStatus == .done,
              let list = dropLayout.nativeList else { return nil }
        var index = list.insertionIndex(at: windowPoint)
        var lane = input.column.songs
        if let own = lane.firstIndex(where: { $0.id == song.id }) {
            if index == own || index == own + 1 { return nil }
            if own < index { index -= 1 }
            lane.remove(at: own)
        }
        return (index, lane)
    }

    /// The line where a drop would land, hidden where it would change nothing.
    private func showDropPlace(for pointer: (songID: String, windowPoint: NSPoint)?) {
        guard let list = dropLayout.nativeList else { return }
        guard let pointer,
              let song = input.viewModel.songs.first(where: { $0.id == pointer.songID }),
              dropPlace(of: song, at: pointer.windowPoint) != nil else {
            list.showInsertion(at: nil, windowPoint: pointer?.windowPoint)
            return
        }
        list.showInsertion(at: list.insertionIndex(at: pointer.windowPoint), windowPoint: pointer.windowPoint)
    }

    /// Next turn: the lane has laid out the moved row by then.
    private func revealDrop(songID: String) {
        let reduceMotion = input.reduceMotion
        DispatchQueue.main.async { [weak self] in
            self?.dropLayout.nativeList?.revealDroppedSong(songID: songID, reduceMotion: reduceMotion)
        }
    }

    private static func content(input: ArchiveBoardColumnInput, column: ArchiveBoardColumn,
                                state: ArchiveBoardLaneState, targeted: Bool,
                                layout: ArchiveBoardDropLayout) -> ArchiveBoardColumnContent {
        let scrolling = input.boardScroll
        return ArchiveBoardColumnContent(
            column: column, viewModel: input.viewModel,
            selectedSongID: state.selectedSong.flatMap { $0.workflowStatus == column.status ? $0.id : nil },
            vaultPresentations: state.vaultPresentations, vaultActivity: state.vaultActivity,
            isCompact: input.compactWhenEmpty && !targeted, isDropTargeted: targeted,
            colorScheme: input.colorScheme, dropLayout: layout, isBoardVisible: state.isBoardVisible,
            onInteract: { scrolling.onInteract() }, boardScroll: scrolling
        )
    }
}

struct ArchiveBoardLaneState: Equatable {
    let selectedSong: Song?
    let vaultPresentations: [String: ProjectVaultCardPresentation]
    let vaultActivity: [String: String]
    let isBoardVisible: Bool
}

extension ArchiveBoardLaneState {
    @MainActor
    init(viewModel: ArchiveBrowserViewModel) {
        selectedSong = viewModel.page.selectedSong
        vaultPresentations = viewModel.projectVaultPresentationsBySongID
        vaultActivity = viewModel.projectVaultActivityMessages
        isBoardVisible = viewModel.page.showsBoardPage
    }
}

/// A named hosting root keeps SwiftUI's dynamic-property discovery at the lane
/// boundary small. Every changing render input is a value here, so selection,
/// Vault activity and catalog updates still invalidate the hosted contents.
struct ArchiveBoardColumnContent: View {
    let column: ArchiveBoardColumn
    let viewModel: ArchiveBrowserViewModel
    let selectedSongID: String?
    let vaultPresentations: [String: ProjectVaultCardPresentation]
    let vaultActivity: [String: String]
    let isCompact: Bool
    let isDropTargeted: Bool
    let colorScheme: ColorScheme
    let dropLayout: ArchiveBoardDropLayout
    let isBoardVisible: Bool
    let onInteract: () -> Void
    let boardScroll: ArchiveBoardScrollController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            columnHeader(column)

            ArchiveBoardSongsView(
                songs: column.songs,
                selectedSongID: selectedSongID,
                vaultPresentations: vaultPresentations,
                vaultActivity: vaultActivity,
                viewModel: viewModel,
                dropLayout: dropLayout,
                isBoardVisible: isBoardVisible,
                onInteract: onInteract,
                boardScroll: boardScroll
            )
            .equatable()

            if column.songs.isEmpty {
                Spacer(minLength: 0)
            }
        }
        .padding(ArchiveBoardLaneLayout.padding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous)
                .fill(isDropTargeted ? HubDesignSystem.Palette.accentFill : HubDesignSystem.Palette.surface)
        }
        .environment(\.colorScheme, colorScheme)
        .simultaneousGesture(TapGesture().onEnded(onInteract))
        .coordinateSpace(name: "archive-board-drop-column")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(column.accessibilityLabel)
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

}
