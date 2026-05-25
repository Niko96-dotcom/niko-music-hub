import Foundation

/// Operator-facing strings for the archive diagnostics panel (parity with export `summary_line=`).
public struct ArchiveDiagnosticsPanelContext: Sendable, Equatable {
    /// Pasteable support-ticket line: redacted roots plus scan counts (no `summary_line=` prefix).
    public let supportSummaryLine: String

    public init(supportSummaryLine: String) {
        self.supportSummaryLine = supportSummaryLine
    }

    public static func from(
        _ diagnostics: ArchiveScanDiagnostics,
        homeDirectory: String? = nil
    ) -> ArchiveDiagnosticsPanelContext {
        ArchiveDiagnosticsPanelContext(
            supportSummaryLine: diagnostics.exportSummaryLine(homeDirectory: homeDirectory)
        )
    }
}
