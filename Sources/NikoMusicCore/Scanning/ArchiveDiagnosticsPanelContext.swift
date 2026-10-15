import Foundation

/// Operator-facing strings for the archive diagnostics panel (parity with export `summary_line=`).
public struct ArchiveDiagnosticsPanelContext: Sendable, Equatable {
    /// Pasteable support-ticket line: redacted roots plus scan counts (no `summary_line=` prefix).
    public let supportSummaryLine: String
    /// Compact scan-health badge for root issues, song warnings, and skipped-at-roots entries; nil when fully clean.
    public let rootHealthBadge: String?
    /// Footnote when the support summary omits warning song titles beyond the cap; nil when not truncated.
    public let supportSummaryTruncationFootnote: String?

    public init(
        supportSummaryLine: String,
        rootHealthBadge: String? = nil,
        supportSummaryTruncationFootnote: String? = nil
    ) {
        self.supportSummaryLine = supportSummaryLine
        self.rootHealthBadge = rootHealthBadge
        self.supportSummaryTruncationFootnote = supportSummaryTruncationFootnote
    }

    public static func from(
        _ diagnostics: ArchiveScanDiagnostics,
        homeDirectory: String? = nil
    ) -> ArchiveDiagnosticsPanelContext {
        ArchiveDiagnosticsPanelContext(
            supportSummaryLine: diagnostics.exportSummaryLine(homeDirectory: homeDirectory),
            rootHealthBadge: rootHealthBadge(for: diagnostics),
            supportSummaryTruncationFootnote: diagnostics.summaryLineSongWarningTitlesTruncationFootnote
        )
    }

    public static func rootHealthBadge(for diagnostics: ArchiveScanDiagnostics) -> String? {
        let invalidRootCount = diagnostics.skippedEntries.filter { $0.kind == .invalidRoot }.count
        let globalWarningCount = diagnostics.globalWarnings.count
        let songWarningCount = diagnostics.songsWithWarningsCount
        let skippedAtRootsCount = diagnostics.skippedEntries.filter { $0.kind != .invalidRoot }.count

        guard invalidRootCount > 0
            || globalWarningCount > 0
            || songWarningCount > 0
            || skippedAtRootsCount > 0 else {
            return nil
        }

        var parts: [String] = []
        if invalidRootCount > 0 {
            parts.append(CountCopy.count(invalidRootCount, "invalid root"))
        }
        if globalWarningCount > 0 {
            parts.append(CountCopy.count(globalWarningCount, "root warning"))
        }
        if songWarningCount > 0 {
            parts.append(CountCopy.count(songWarningCount, "song warning"))
        }
        if skippedAtRootsCount > 0 {
            parts.append("\(skippedAtRootsCount) skipped at roots")
        }
        return parts.joined(separator: " · ")
    }
}
