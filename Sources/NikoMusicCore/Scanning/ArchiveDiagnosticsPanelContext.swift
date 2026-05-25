import Foundation

/// Operator-facing strings for the archive diagnostics panel (parity with export `summary_line=`).
public struct ArchiveDiagnosticsPanelContext: Sendable, Equatable {
    /// Pasteable support-ticket line: redacted roots plus scan counts (no `summary_line=` prefix).
    public let supportSummaryLine: String
    /// Compact badge when archive roots have global warnings or invalid-root skips; nil when healthy.
    public let rootHealthBadge: String?

    public init(supportSummaryLine: String, rootHealthBadge: String? = nil) {
        self.supportSummaryLine = supportSummaryLine
        self.rootHealthBadge = rootHealthBadge
    }

    public static func from(
        _ diagnostics: ArchiveScanDiagnostics,
        homeDirectory: String? = nil
    ) -> ArchiveDiagnosticsPanelContext {
        ArchiveDiagnosticsPanelContext(
            supportSummaryLine: diagnostics.exportSummaryLine(homeDirectory: homeDirectory),
            rootHealthBadge: rootHealthBadge(for: diagnostics)
        )
    }

    public static func rootHealthBadge(for diagnostics: ArchiveScanDiagnostics) -> String? {
        let invalidRootCount = diagnostics.skippedEntries.filter { $0.kind == .invalidRoot }.count
        let warningCount = diagnostics.globalWarnings.count
        guard invalidRootCount > 0 || warningCount > 0 else {
            return nil
        }

        var parts: [String] = []
        if invalidRootCount > 0 {
            let noun = invalidRootCount == 1 ? "invalid root" : "invalid roots"
            parts.append("\(invalidRootCount) \(noun)")
        }
        if warningCount > 0 {
            let noun = warningCount == 1 ? "root warning" : "root warnings"
            parts.append("\(warningCount) \(noun)")
        }
        return parts.joined(separator: " · ")
    }
}
