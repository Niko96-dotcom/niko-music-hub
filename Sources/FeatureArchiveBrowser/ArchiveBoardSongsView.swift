import AppCore
import NikoMusicCore
import SwiftUI

/// Keep search typing and unrelated progress publications outside the lazy
/// collection. Songs, selection and Vault changes still update the collection;
/// individual cards compare their own inputs.
struct ArchiveBoardSongsView: View, Equatable {
    let songs: [Song]
    let selectedSongID: String?
    let vaultPresentations: [String: ProjectVaultCardPresentation]
    let viewModel: ArchiveBrowserViewModel

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selectedSongID == rhs.selectedSongID
            && lhs.viewModel === rhs.viewModel
            && lhs.songs == rhs.songs
            && lhs.vaultPresentations == rhs.vaultPresentations
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(songs, id: \.id) { song in
                    ArchiveBoardSongCard(
                        song: song,
                        isSelected: selectedSongID == song.id,
                        vaultPresentation: vaultPresentations[song.id],
                        viewModel: viewModel
                    )
                    .equatable()
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ArchiveBoardCardFramesKey.self,
                                value: [song.id: proxy.frame(in: .named("archive-board-drop-column"))]
                            )
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 4)),
                        removal: .opacity
                    ))
                }
            }
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
    let viewModel: ArchiveBrowserViewModel

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isSelected == rhs.isSelected
            && lhs.vaultPresentation == rhs.vaultPresentation
            && lhs.viewModel === rhs.viewModel
            && lhs.song == rhs.song
    }

    var body: some View {
        ArchiveBoardCardView(
            song: song,
            isSelected: isSelected,
            vaultPresentation: vaultPresentation,
            onSelect: { viewModel.selectSongOnBoard(song) },
            onOpenDetail: { viewModel.selectSong(song) },
            onProjectVaultPrimaryAction: {
                viewModel.performProjectVaultPrimaryAction(for: song)
            }
        )
    }
}
