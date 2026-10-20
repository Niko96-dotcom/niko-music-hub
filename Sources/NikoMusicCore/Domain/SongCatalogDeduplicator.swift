import Foundation

/// Preserves the first occurrence and catalog order while enforcing Song's path-based identity.
/// Scan roots may legitimately overlap in settings (for example Scan-only + Vault Active), but
/// downstream browse and intelligence code must always receive one row per physical song path.
public enum SongCatalogDeduplicator {
    public static func uniqueByID(_ songs: [Song]) -> [Song] {
        var seen = Set<String>(minimumCapacity: songs.count)
        guard let firstRepeat = songs.firstIndex(where: { !seen.insert($0.id).inserted }) else {
            // The usual catalog has no repeat: hand it back as it is (no 10,000-song copy, and the same storage,
            // which later comparisons recognize at once).
            return songs
        }
        var unique = Array(songs[..<firstRepeat])
        unique.reserveCapacity(songs.count - 1)
        for song in songs[(firstRepeat + 1)...] where seen.insert(song.id).inserted {
            unique.append(song)
        }
        return unique
    }

    /// Cache loading and scanning independently allocate the same catalog.
    /// Reuse equal immutable values so browse/card caches and the live snapshot
    /// share their nested arrays and URLs. Every field participates in equality;
    /// changed, added and removed songs always follow the incoming snapshot.
    public static func sharingUnchangedValues(_ songs: [Song], from previous: [Song]) -> [Song] {
        if songs.equalsConcurrently(previous) { return previous }
        let byID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ParallelMap.map(songs) { song in
            guard let old = byID[song.id], old == song else { return song }
            return old
        }
    }
}
