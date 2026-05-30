import Foundation

extension ArchiveBrowseFilter {
    /// Filters shown in the archive sidebar, in display order.
    public static let sidebarOrder: [ArchiveBrowseFilter] = [.hasStems, .noPreview, .hasWarnings]

    public var sidebarSymbolName: String {
        if self == .hasStems { return "waveform.path" }
        if self == .noPreview { return "speaker.slash" }
        if self == .hasWarnings { return "exclamationmark.triangle" }
        return "line.3.horizontal.decrease.circle"
    }

    public var sidebarAccessibilityLabel: String {
        if self == .hasStems { return "Songs with stems" }
        if self == .noPreview { return "Songs missing a preview" }
        if self == .hasWarnings { return "Songs with scan warnings" }
        return "Filter"
    }
}
