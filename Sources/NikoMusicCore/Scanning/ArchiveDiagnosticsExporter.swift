import Foundation

public enum ArchiveDiagnosticsExportError: Error, Equatable, Sendable {
    case destinationInsideArchiveRoot
}

public enum ArchiveDiagnosticsExporter {
    public static func exportText(
        diagnostics: ArchiveScanDiagnostics,
        to destination: URL,
        archiveRoots: [URL],
        homeDirectory: String? = nil
    ) throws {
        let destinationPath = destination.standardizedFileURL.path
        for root in archiveRoots {
            let rootPath = root.standardizedFileURL.path
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            if destinationPath == rootPath || destinationPath.hasPrefix(prefix) {
                throw ArchiveDiagnosticsExportError.destinationInsideArchiveRoot
            }
        }

        let text = formattedText(diagnostics: diagnostics, homeDirectory: homeDirectory)
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }

    static func formattedText(
        diagnostics: ArchiveScanDiagnostics,
        homeDirectory: String?
    ) -> String {
        var lines: [String] = []
        lines.append("Niko Music Hub — archive scan diagnostics")
        lines.append("scanned_at=\(ISO8601DateFormatter().string(from: diagnostics.scannedAt))")
        lines.append("songs=\(diagnostics.songCount)")
        lines.append("songs_with_warnings=\(diagnostics.songsWithWarningsCount)")
        lines.append("total_song_warnings=\(diagnostics.totalSongWarningCount)")

        if diagnostics.rootPaths.isEmpty {
            lines.append("roots=(none)")
        } else {
            for root in diagnostics.rootPaths {
                lines.append("root=\(DiagnosticsPathRedactor.redact(root, homeDirectory: homeDirectory))")
            }
        }

        for warning in diagnostics.globalWarnings {
            lines.append("global_warning=\(DiagnosticsPathRedactor.redact(warning, homeDirectory: homeDirectory))")
        }

        for summary in diagnostics.songWarningSummaries {
            lines.append("song=\(summary.displayTitle)")
            for warning in summary.warnings {
                lines.append("  warning=\(warning)")
            }
        }

        for entry in diagnostics.skippedEntries {
            let label = DiagnosticsPathRedactor.redact(entry.label, homeDirectory: homeDirectory)
            lines.append("skipped=\(entry.kind.rawValue) label=\(label) reason=\(entry.reason)")
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
