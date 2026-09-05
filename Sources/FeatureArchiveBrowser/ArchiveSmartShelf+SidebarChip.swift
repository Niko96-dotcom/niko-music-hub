import NikoMusicCore

extension ArchiveSmartShelf {
    /// Short label for horizontal shelf chips in the archive sidebar.
    var sidebarChipTitle: String {
        switch self {
        case .allSongs: "All"
        case .recentlyBounced: "Recent"
        case .recentCPRActivity: "Projects"
        case .hasStems: "Stems"
        case .byCollaborator: "Collabs"
        case .quietSongs: "Quiet"
        }
    }
}
