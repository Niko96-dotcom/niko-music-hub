import Foundation

/// Operator-facing scan count rows for the archive diagnostics panel (parity with export count lines).
public enum ArchiveDiagnosticsScanCountsPanelContext: Sendable {
    public static func panelSongsValue(songCount: Int) -> String {
        "\(songCount)"
    }

    public static func panelSongWarningsValue(
        songsWithWarningsCount: Int,
        totalSongWarningCount: Int
    ) -> String {
        "\(songsWithWarningsCount) (\(totalSongWarningCount) total)"
    }

    public static func exportSongsLine(songCount: Int) -> String {
        "songs=\(songCount)"
    }

    public static func exportSongsWithWarningsLine(songsWithWarningsCount: Int) -> String {
        "songs_with_warnings=\(songsWithWarningsCount)"
    }

    public static func exportTotalSongWarningsLine(totalSongWarningCount: Int) -> String {
        "total_song_warnings=\(totalSongWarningCount)"
    }

    public static func countsMatchExport(
        in exportText: String,
        diagnostics: ArchiveScanDiagnostics
    ) -> Bool {
        exportText.contains(exportSongsLine(songCount: diagnostics.songCount))
            && exportText.contains(
                exportSongsWithWarningsLine(songsWithWarningsCount: diagnostics.songsWithWarningsCount)
            )
            && exportText.contains(
                exportTotalSongWarningsLine(totalSongWarningCount: diagnostics.totalSongWarningCount)
            )
    }
}
