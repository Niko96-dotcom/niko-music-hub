import NikoMusicCore

enum SongCardAccessibility {
    static func summary(song: Song) -> String {
        let status = song.workflowStatus?.displayTitle ?? "No Status"
        var parts = ["\(song.effectiveDisplayTitle), \(status)"]
        let warning = warningValue(song: song)
        if !warning.isEmpty {
            parts.append(warning)
        }
        return parts.joined(separator: ", ")
    }

    static func warningValue(song: Song) -> String {
        let warnings = song.displayScanWarnings()
        guard !warnings.isEmpty else { return "" }
        return "Warning: \(warnings.joined(separator: " "))"
    }
}
