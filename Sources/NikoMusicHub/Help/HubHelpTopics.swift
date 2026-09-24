import Foundation

/// In-app Help catalog (NMH-014). Identifiers, menu titles, section copy, and anchors.
/// No Help Book / `CFBundleHelpBookName` — the Help window is the documentation.
struct HubHelpTopic: Hashable, Identifiable, Sendable {
    let id: String
    let menuTitle: String
    let heading: String
    let body: String
    let anchor: String

    var url: URL {
        URL(string: "nikomusichub:help#\(anchor)")!
    }
}

enum HubHelpTopics {
    static let windowID = "help"
    static let windowTitle = "Niko Music Hub Help"

    static let archiveRoots = HubHelpTopic(
        id: "archive-roots",
        menuTitle: "Archive Roots",
        heading: "Archive roots",
        body: "Choose the folders that contain Cubase or Ableton projects. Niko Music Hub scans them read-only unless you confirm a Project Vault transfer.",
        anchor: "archive-roots"
    )

    static let helperTools = HubHelpTopic(
        id: "helper-tools",
        menuTitle: "Helper Tools",
        heading: "Helper tools",
        body: "Downloader needs yt-dlp and FFmpeg. Stem Separation needs demucs-mlx. Choose Help → Set Up Helper Tools… to install them in one step; they go into the app's own folder. To use copies you installed yourself, set their paths in Settings → Helpers.",
        anchor: "helper-tools"
    )

    static let projectVault = HubHelpTopic(
        id: "project-vault",
        menuTitle: "Project Vault",
        heading: "Project Vault",
        body: "Archive Now copies a project to the vault, verifies it, then deletes the Active folder after you confirm. Create Backup Copy verifies a copy and keeps Active. Restore & Open never overwrites an existing Active folder.",
        anchor: "project-vault"
    )

    static let outputInbox = HubHelpTopic(
        id: "output-inbox",
        menuTitle: "Output Inbox",
        heading: "Output Inbox",
        body: "Exports, recordings, downloads, and stems appear in the Output Inbox. Reveal in Finder from that pane or the tool shelf.",
        anchor: "output-inbox"
    )

    static let all: [HubHelpTopic] = [
        archiveRoots,
        helperTools,
        projectVault,
        outputInbox,
    ]
}
