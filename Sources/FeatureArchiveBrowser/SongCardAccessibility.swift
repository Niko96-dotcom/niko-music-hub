import NikoMusicCore

enum SongCardAccessibility {
    static func summary(song: Song) -> String {
        let status = song.workflowStatus?.displayTitle ?? "No Status"
        var parts = ["\(song.effectiveDisplayTitle), \(status)"]
        let warnings = song.displayScanWarnings()
        if !warnings.isEmpty {
            parts.append("Warning: \(warnings.joined(separator: " "))")
        }
        return parts.joined(separator: ", ")
    }
}
