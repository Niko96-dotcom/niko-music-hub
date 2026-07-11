import Foundation
import NikoMusicCore

/// One month band on the archive timeline, newest first.
struct ArchiveTimelineMonth: Equatable, Identifiable {
    let id: String
    let monthStart: Date
    var entries: [ArchiveTimelineEntry]

    var versionCount: Int {
        entries.reduce(0) { $0 + $1.versionCount }
    }
}

/// A song's CPR activity within one month.
struct ArchiveTimelineEntry: Equatable, Identifiable {
    let id: String
    let song: Song
    let versionCount: Int
    let latestActivity: Date
}

/// Pure timeline projection: buckets each song's visible CPR versions by
/// month of last modification, derived entirely from scanned archive data.
enum ArchiveTimelineProjection {
    static func months(from songs: [Song], calendar: Calendar = .current) -> [ArchiveTimelineMonth] {
        var buckets: [Date: [String: (song: Song, count: Int, latest: Date)]] = [:]
        for song in songs {
            for version in song.visibleProjectVersions {
                let components = calendar.dateComponents([.year, .month], from: version.modifiedAt)
                guard let monthStart = calendar.date(from: components) else { continue }
                var entries = buckets[monthStart] ?? [:]
                if let existing = entries[song.id] {
                    entries[song.id] = (
                        song,
                        existing.count + 1,
                        max(existing.latest, version.modifiedAt)
                    )
                } else {
                    entries[song.id] = (song, 1, version.modifiedAt)
                }
                buckets[monthStart] = entries
            }
        }
        return buckets
            .sorted { $0.key > $1.key }
            .map { monthStart, entriesBySong in
                let monthID = monthKey(monthStart, calendar: calendar)
                let entries = entriesBySong.values
                    .sorted { $0.latest > $1.latest }
                    .map { entry in
                        ArchiveTimelineEntry(
                            id: "\(monthID)|\(entry.song.id)",
                            song: entry.song,
                            versionCount: entry.count,
                            latestActivity: entry.latest
                        )
                    }
                return ArchiveTimelineMonth(id: monthID, monthStart: monthStart, entries: entries)
            }
    }

    private static func monthKey(_ monthStart: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
}
