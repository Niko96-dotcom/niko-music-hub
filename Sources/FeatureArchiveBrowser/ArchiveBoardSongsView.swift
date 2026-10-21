import AppCore
import NikoMusicCore
import SwiftUI

/// Keep search typing and unrelated progress publications outside the scrolling
/// collection. Songs, selection and Vault changes still update the collection;
/// individual cards compare their own inputs.
struct ArchiveBoardSongsView: View, Equatable {
    let songs: [Song]
    let selectedSongID: String?
    let vaultPresentations: [String: ProjectVaultCardPresentation]
    var vaultActivity: [String: String] = [:]
    let viewModel: ArchiveBrowserViewModel
    let dropLayout: ArchiveBoardDropLayout
    var isBoardVisible = true
    var onInteract: () -> Void = {}
    var boardScroll: ArchiveBoardScrollController? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selectedSongID == rhs.selectedSongID
            && lhs.viewModel === rhs.viewModel
            && lhs.dropLayout === rhs.dropLayout
            && lhs.isBoardVisible == rhs.isBoardVisible
            && lhs.boardScroll === rhs.boardScroll
            && lhs.songs.equalsConcurrently(rhs.songs)
            && lhs.vaultPresentations == rhs.vaultPresentations
            && lhs.vaultActivity == rhs.vaultActivity
    }

    var body: some View {
        ArchiveBoardNativeSongList(
            songs: songs,
            selectedSongID: selectedSongID,
            vaultPresentations: vaultPresentations,
            vaultActivity: vaultActivity,
            viewModel: viewModel,
            dropLayout: dropLayout,
            colorScheme: colorScheme,
            reduceMotion: reduceMotion,
            isBoardVisible: isBoardVisible,
            onInteract: onInteract,
            boardScroll: boardScroll
        )
        .onMoveCommand { direction in
            viewModel.moveSongSelection(ArchiveSongMoveDirection(direction))
        }
    }
}

/// The archive model publishes search text, progress, and analysis independently
/// of a card's contents. Compare the actual card inputs before rebuilding its
/// controls. Actions are derived from the model identity here, so equality never
/// discards a changed callback supplied by a caller.
struct ArchiveBoardSongCard: View, Equatable {
    let song: Song
    let isSelected: Bool
    let vaultPresentation: ProjectVaultCardPresentation?
    var vaultActivityMessage: String? = nil
    let viewModel: ArchiveBrowserViewModel
    var scrollActivity: ArchiveBoardScrollActivity? = nil

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isSelected == rhs.isSelected
            && lhs.vaultPresentation == rhs.vaultPresentation
            && lhs.vaultActivityMessage == rhs.vaultActivityMessage
            && lhs.viewModel === rhs.viewModel
            && lhs.scrollActivity === rhs.scrollActivity
            && lhs.song == rhs.song
    }

    var body: some View {
        ArchiveBoardCardView(
            song: song,
            isSelected: isSelected,
            vaultPresentation: vaultPresentation,
            vaultActivityMessage: vaultActivityMessage,
            onSelect: { viewModel.selectSongOnBoard(song) },
            onOpenDetail: { viewModel.openSongDetail(song) },
            onProjectVaultPrimaryAction: {
                viewModel.performProjectVaultPrimaryAction(for: song)
            },
            onPlay: { viewModel.audition(song) },
            onOpenProject: { try? viewModel.openLatestCPR(for: song) },
            onRevealInFinder: { viewModel.revealInFinder(url: viewModel.preferredRevealURL(for: song)) },
            canRevealInFinder: viewModel.preferredRevealURL(for: song) != nil,
            onWorkflowStatusChange: { viewModel.applyWorkflowStatus($0, for: song) },
            scrollActivity: scrollActivity
        )
    }
}
