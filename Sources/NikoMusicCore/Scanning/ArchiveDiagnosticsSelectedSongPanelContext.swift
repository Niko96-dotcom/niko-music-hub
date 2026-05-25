import Foundation

/// Operator-facing selected song lines for the archive diagnostics panel (parity with export `selected_song`).
public enum ArchiveDiagnosticsSelectedSongPanelContext: Sendable {
    public static func panelTitleLine(displayTitle: String) -> String {
        displayTitle
    }

    public static func panelCprLine(cprSummary: String) -> String {
        "CPR · \(cprSummary)"
    }

    public static func panelWarningLine(warning: String) -> String {
        warning
    }

    public static func panelNotesLine(notes: String) -> String {
        "Notes · \(notes)"
    }

    public static func titleLineMatchesExport(in exportText: String, displayTitle: String) -> Bool {
        exportText.contains("selected_song_title=\(displayTitle)")
    }

    public static func cprLineMatchesExport(in exportText: String, cprSummary: String) -> Bool {
        exportText.contains("selected_song_cpr=\(cprSummary)")
    }

    public static func warningLinesMatchExport(in exportText: String, warningLines: [String]) -> Bool {
        guard !warningLines.isEmpty else { return false }
        return warningLines.allSatisfy { warning in
            exportText.contains("selected_song_warning=\(warning)")
        }
    }

    public static func notesLineMatchesExport(in exportText: String, notes: String) -> Bool {
        guard !notes.isEmpty else { return false }
        return exportText.contains("selected_song_notes=\(notes)")
    }
}
