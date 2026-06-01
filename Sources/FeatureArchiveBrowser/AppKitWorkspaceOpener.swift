import AppKit
import NikoMusicCore

struct AppKitWorkspaceOpener: WorkspaceOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
