import NikoMusicCore
import SwiftUI

/// Shared list / board / Song-menu command model (NMH-046).
/// `pausePreview` occupies the same slot as `playPreview`.
public enum SongItemCommand: Equatable, CaseIterable, Sendable {
    case openProject
    case playPreview
    case pausePreview
    case revealInFinder
    case workflowStatus

    public static let menuOrder: [SongItemCommand] = [
        .openProject, .playPreview, .revealInFinder, .workflowStatus,
    ]
}

public enum SongItemCommandCopy {
    public static let openProject = "Open Project"
    public static let playPreview = "Play Preview"
    public static let pausePreview = "Pause Preview"
    public static let revealInFinder = "Reveal in Finder"

    public static func previewTitle(isPlaying: Bool) -> String {
        isPlaying ? pausePreview : playPreview
    }
}

/// Context-menu and overflow items for one song. Keyboard shortcuts stay on the Song menu.
struct SongItemCommands: View {
    let song: Song
    let isPreviewPlaying: Bool
    let canOpenProject: Bool
    let canPlayPreview: Bool
    let canRevealInFinder: Bool
    var allowsWorkflowMutation: Bool = true
    var showsWorkflowStatus: Bool = true
    let onOpenProject: () -> Void
    let onPlayPreview: () -> Void
    let onRevealInFinder: () -> Void
    var onWorkflowStatusChange: ((ProjectWorkflowStatus?) -> Void)? = nil

    var body: some View {
        Button(SongItemCommandCopy.openProject, action: onOpenProject)
            .disabled(!canOpenProject)
        Button(SongItemCommandCopy.previewTitle(isPlaying: isPreviewPlaying), action: onPlayPreview)
            .disabled(!canPlayPreview)
        Button(SongItemCommandCopy.revealInFinder, action: onRevealInFinder)
            .disabled(!canRevealInFinder)
        if showsWorkflowStatus {
            Divider()
            Menu(SongWorkflowActions.songMenuTitle) {
                SongWorkflowContextMenu(
                    allowsMutation: true,
                    onSelect: onWorkflowStatusChange
                )
            }
            .disabled(!allowsWorkflowMutation || onWorkflowStatusChange == nil)
        }
    }
}

extension SongItemCommands {
    init(
        song: Song,
        isPreviewPlaying: Bool,
        captureActive: Bool,
        canRevealInFinder: Bool,
        allowsWorkflowMutation: Bool,
        showsWorkflowStatus: Bool = true,
        onOpenProject: @escaping () -> Void,
        onPlayPreview: @escaping () -> Void,
        onRevealInFinder: @escaping () -> Void,
        onWorkflowStatusChange: ((ProjectWorkflowStatus?) -> Void)?
    ) {
        self.init(
            song: song,
            isPreviewPlaying: isPreviewPlaying,
            canOpenProject: song.effectiveLatestCPR != nil,
            canPlayPreview: song.mainPreviewURL != nil && !captureActive,
            canRevealInFinder: canRevealInFinder,
            allowsWorkflowMutation: allowsWorkflowMutation,
            showsWorkflowStatus: showsWorkflowStatus,
            onOpenProject: onOpenProject,
            onPlayPreview: onPlayPreview,
            onRevealInFinder: onRevealInFinder,
            onWorkflowStatusChange: onWorkflowStatusChange
        )
    }
}
