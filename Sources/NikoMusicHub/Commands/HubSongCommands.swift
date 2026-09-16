import FeatureArchiveBrowser
import NikoMusicCore
import SwiftUI

/// Song menu: labeled archive letter shortcuts (NMH-034).
/// Unmodified keys stay archive-focused; Find keeps ⌘F (NMH-033).
struct HubSongCommands: Commands {
    @FocusedValue(\.archiveSongActions) private var focusedActions
    @ObservedObject private var commandContext = ArchiveSongCommandContext.shared

    private var songActions: ArchiveSongFocusedActions? { focusedActions ?? commandContext.actions }

    var body: some Commands {
        CommandMenu("Song") {
            Button("Play/Pause Preview") {
                songActions?.playPausePreview()
            }
            .help("Space when the archive is focused")
            .disabled(songActions == nil)

            Button("Open Project") {
                songActions?.openProject()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(songActions?.hasSelectedSong != true)

            Button("Reveal in Finder") {
                songActions?.revealInFinder()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(songActions?.hasSelectedSong != true)

            Button("Reveal in Finder") {
                songActions?.revealInFinder()
            }
            .keyboardShortcut("f", modifiers: [])
            .disabled(songActions?.allowsUnmodifiedShortcuts != true || songActions?.hasSelectedSong != true)

            Button("Show Versions") {
                songActions?.showVersions()
            }
            .keyboardShortcut("d", modifiers: [])
            .disabled(songActions?.allowsUnmodifiedShortcuts != true || songActions?.hasSelectedSong != true)

            Button("Open Preview") {
                songActions?.openPreview()
            }
            .keyboardShortcut("p", modifiers: [])
            .disabled(songActions?.allowsUnmodifiedShortcuts != true || songActions?.hasSelectedSong != true)

            Divider()

            Menu(SongWorkflowActions.songMenuTitle) {
                Button(SongWorkflowActions.clearStatusMenuTitle) {
                    songActions?.applyWorkflowStatus(nil)
                }
                ForEach(ProjectWorkflowStatus.allCases, id: \.self) { status in
                    Button(status.displayTitle) {
                        songActions?.applyWorkflowStatus(status)
                    }
                }
            }
            .disabled(songActions?.hasSelectedSong != true || songActions?.allowsWorkflowMutation != true)
        }
    }
}
