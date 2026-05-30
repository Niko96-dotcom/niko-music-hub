import NikoMusicCore

extension ArchiveBrowseFilter {
    private struct SidebarChipMetadata {
        let filter: ArchiveBrowseFilter
        let symbolName: String
        let accessibilityLabel: String
    }

    private static let sidebarChipMetadata: [SidebarChipMetadata] = [
        SidebarChipMetadata(
            filter: .hasStems,
            symbolName: "waveform.path",
            accessibilityLabel: "Songs with stems"
        ),
        SidebarChipMetadata(
            filter: .noPreview,
            symbolName: "speaker.slash",
            accessibilityLabel: "Songs missing a preview"
        ),
        SidebarChipMetadata(
            filter: .hasWarnings,
            symbolName: "exclamationmark.triangle",
            accessibilityLabel: "Songs with scan warnings"
        ),
    ]

    /// Single-filter chips shown in the archive sidebar, in display order.
    static let sidebarFilters: [ArchiveBrowseFilter] = sidebarChipMetadata.map(\.filter)

    var sidebarSymbolName: String {
        Self.metadata(for: self)?.symbolName ?? "line.3.horizontal.decrease.circle"
    }

    var sidebarAccessibilityLabel: String {
        Self.metadata(for: self)?.accessibilityLabel ?? "Filter"
    }

    private static func metadata(for filter: ArchiveBrowseFilter) -> SidebarChipMetadata? {
        sidebarChipMetadata.first { filter == $0.filter }
    }
}
