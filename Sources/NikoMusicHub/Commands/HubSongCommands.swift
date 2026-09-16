import AppCore
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
            Button("New Song Draft") {
                NotificationCenter.default.post(name: .archiveNewSongDraftRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button(SongItemCommandCopy.openProject) {
                songActions?.openProject()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(songActions?.hasSelectedSong != true)

            Button(SongItemCommandCopy.previewTitle(isPlaying: songActions?.isPreviewPlaying == true)) {
                songActions?.playPausePreview()
            }
            .help("Space when the archive is focused")
            .disabled(songActions == nil)

            Button(SongItemCommandCopy.revealInFinder) {
                songActions?.revealInFinder()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(songActions?.hasSelectedSong != true)

            Button(SongItemCommandCopy.revealInFinder) {
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

            Button("Skip Back 5 Seconds") {
                songActions?.skipPreviewBack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .option)
            .disabled(songActions?.canSkipPreview != true)

            Button("Skip Forward 5 Seconds") {
                songActions?.skipPreviewForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: .option)
            .disabled(songActions?.canSkipPreview != true)

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
