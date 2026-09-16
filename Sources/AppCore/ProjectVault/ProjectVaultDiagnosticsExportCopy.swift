import Foundation

/// NMH-055: user-facing copy and dated filenames for Project Vault diagnostics export.
/// The export body stays path-free; only the presentation (Save panel, dated name,
/// replace confirmation) changed.
public enum ProjectVaultDiagnosticsExportCopy: Sendable {
    /// Dated default filename, e.g. `project-vault-diagnostics-2026-09-15.txt`.
    /// Gregorian calendar; the time zone defaults to the person's local zone so the
    /// panel suggestion matches the date they see. Tests pass an explicit calendar
    /// and time zone for determinism.
    public static func filename(
        for date: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "project-vault-diagnostics-%04d-%02d-%02d.txt", year, month, day)
    }

    /// Convenience for production call sites (local calendar and time zone).
    public static func filename(for date: Date = Date()) -> String {
        filename(for: date, calendar: Calendar(identifier: .gregorian), timeZone: .current)
    }

    public static let savePrompt = "Export"

    public static let saveMessage = "Choose where to save Project Vault diagnostics."

    public static let replaceTitle = "Replace this file?"

    public static func replaceMessage(filename: String) -> String {
        "A file named “\(filename)” already exists in this folder. Replacing it cannot be undone from Niko Music Hub."
    }

    public static let archiveRootRecoveryMessage =
        "Diagnostics export failed: the chosen location is inside an archive folder. Choose a folder outside the archive and try again."
}
