import AppCore
import NikoMusicCore
import SwiftUI

/// Compact archive sidebar controls so the song list stays visible.
enum ArchiveSidebarChrome {
    static func filterIcon(_ filter: ArchiveBrowseFilter) -> String {
        if filter == .hasStems { return "waveform.path" }
        if filter == .noPreview { return "speaker.slash" }
        if filter == .hasWarnings { return "exclamationmark.triangle" }
        return "line.3.horizontal.decrease.circle"
    }

    static func filterHelp(_ filter: ArchiveBrowseFilter) -> String {
        if filter == .hasStems { return "Songs with stems" }
        if filter == .noPreview { return "Songs missing a preview" }
        if filter == .hasWarnings { return "Songs with scan warnings" }
        return "Filter"
    }

    static let filterOrder: [ArchiveBrowseFilter] = [.hasStems, .noPreview, .hasWarnings]
}

struct ArchiveFilterIconToggle: View {
    let filter: ArchiveBrowseFilter
    let active: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: ArchiveSidebarChrome.filterIcon(filter))
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(active ? .white : ArchiveDesignTokens.textSecondary)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? ArchiveDesignTokens.accent : Color.primary.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            active ? ArchiveDesignTokens.accent : Color.primary.opacity(0.12),
                            lineWidth: active ? 1.5 : 1
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(ArchiveSidebarChrome.filterHelp(filter))
        .accessibilityValue(active ? "On" : "Off")
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(ArchiveSidebarChrome.filterHelp(filter))
    }
}
