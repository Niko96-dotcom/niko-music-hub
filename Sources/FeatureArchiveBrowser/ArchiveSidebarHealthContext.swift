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
            parts.append(CountCopy.count(report.totalSongs, "song"))
        }
        if report.withWarnings > 0 {
            parts.append(CountCopy.count(report.withWarnings, "warning"))
        }
        if skippedEntryCount > 0 {
            parts.append("\(skippedEntryCount) skipped")
        }
        return parts.isEmpty ? "Health & insights" : parts.joined(separator: " · ")
    }
}
