import NikoMusicCore

extension ArchiveBrowseFilter {
    /// Single-filter chips shown in the archive sidebar, in display order.
    static let sidebarFilters: [ArchiveBrowseFilter] = [.hasStems, .noPreview, .hasWarnings]

    var sidebarSymbolName: String {
        if contains(.hasStems) { return "waveform.path" }
        if contains(.noPreview) { return "speaker.slash" }
        if contains(.hasWarnings) { return "exclamationmark.triangle" }
        return "line.3.horizontal.decrease.circle"
    }

    var sidebarAccessibilityLabel: String {
        if contains(.hasStems) { return "Songs with stems" }
        if contains(.noPreview) { return "Songs missing a preview" }
        if contains(.hasWarnings) { return "Songs with scan warnings" }
        return "Filter"
    }
}
