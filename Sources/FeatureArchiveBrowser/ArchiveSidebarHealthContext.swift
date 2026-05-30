import NikoMusicCore

struct ArchiveSidebarHealthContext: Equatable {
    let report: ArchiveHealthReport
    let summary: String

    static func make(report: ArchiveHealthReport, skippedEntryCount: Int) -> ArchiveSidebarHealthContext {
        ArchiveSidebarHealthContext(report: report, summary: summary(for: report, skippedEntryCount: skippedEntryCount))
    }

    private static func summary(for report: ArchiveHealthReport, skippedEntryCount: Int) -> String {
        var parts: [String] = []
        if report.totalSongs > 0 {
            parts.append("\(report.totalSongs) songs")
        }
        if report.withWarnings > 0 {
            parts.append("\(report.withWarnings) warnings")
        }
        if skippedEntryCount > 0 {
            parts.append("\(skippedEntryCount) skipped")
        }
        return parts.isEmpty ? "Health & intelligence" : parts.joined(separator: " · ")
    }
}
