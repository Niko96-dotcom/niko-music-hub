import Foundation

/// Relative-time labels for list rows ("2 min. ago", "yesterday").
///
/// `RelativeDateTimeFormatter` alone prints "in 0 s" for a date that is equal to or a
/// few milliseconds after the reference date, which is exactly what a row shows the
/// moment its item was created. The named style collapses that window to "now".
public enum HubRelativeTime {
    public static func string(for date: Date, relativeTo reference: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: reference)
    }
}
