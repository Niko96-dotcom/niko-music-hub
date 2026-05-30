import NikoMusicCore
import SwiftUI

struct ArchiveBrowseFilterSidebarChip: Identifiable {
    let filter: ArchiveBrowseFilter
    let symbolName: String
    let accessibilityLabel: String

    var id: ArchiveBrowseFilter.RawValue { filter.rawValue }
}

enum ArchiveBrowseFilterSidebar {
    static let chips: [ArchiveBrowseFilterSidebarChip] = [
        ArchiveBrowseFilterSidebarChip(
            filter: .hasStems,
            symbolName: "waveform.path",
            accessibilityLabel: "Songs with stems"
        ),
        ArchiveBrowseFilterSidebarChip(
            filter: .noPreview,
            symbolName: "speaker.slash",
            accessibilityLabel: "Songs missing a preview"
        ),
        ArchiveBrowseFilterSidebarChip(
            filter: .hasWarnings,
            symbolName: "exclamationmark.triangle",
            accessibilityLabel: "Songs with scan warnings"
        ),
    ]
}
