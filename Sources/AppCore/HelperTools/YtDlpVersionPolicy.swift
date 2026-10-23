import Foundation

/// When a yt-dlp build is too old for YouTube: older than 90 days, or older
/// than the last release YouTube needed.
public enum YtDlpVersionPolicy {
    public static let stalenessDays = 90
    public static let youtubeCompatibilityFloor = "2026.08.19"

    public static func parseVersionDate(_ version: String) -> Date? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(20\d{2})\.(\d{2})\.(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges >= 4,
              let yearRange = Range(match.range(at: 1), in: trimmed),
              let monthRange = Range(match.range(at: 2), in: trimmed),
              let dayRange = Range(match.range(at: 3), in: trimmed),
              let year = Int(trimmed[yearRange]),
              let month = Int(trimmed[monthRange]),
              let day = Int(trimmed[dayRange]) else {
            return nil
        }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }

    public static func isStale(version: String, referenceDate: Date = Date()) -> Bool {
        guard let versionDate = parseVersionDate(version) else { return false }
        guard let threshold = effectiveMinimumDate(referenceDate: referenceDate) else { return false }
        return versionDate < threshold
    }

    public static func minimumExpectedVersion(referenceDate: Date = Date()) -> String {
        guard let threshold = effectiveMinimumDate(referenceDate: referenceDate) else {
            return "recent release"
        }
        let components = utcCalendar.dateComponents(
            [.year, .month, .day],
            from: threshold
        )
        guard let year = components.year, let month = components.month, let day = components.day else {
            return "recent release"
        }
        return String(format: "%04d.%02d.%02d", year, month, day)
    }

    /// Version dates are UTC midnight, so the threshold is computed on UTC day boundaries too.
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    private static func effectiveMinimumDate(referenceDate: Date) -> Date? {
        let calendar = utcCalendar
        guard let ageThreshold = calendar.date(
            byAdding: .day,
            value: -stalenessDays,
            to: calendar.startOfDay(for: referenceDate)
        ) else {
            return nil
        }
        guard let compatibilityFloor = parseVersionDate(youtubeCompatibilityFloor) else {
            return ageThreshold
        }
        return max(ageThreshold, compatibilityFloor)
    }
}
