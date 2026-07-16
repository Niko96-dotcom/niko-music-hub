import Foundation

/// Preserves the first occurrence and catalog order while enforcing Song's path-based identity.
/// Scan roots may legitimately overlap in settings (for example Scan-only + Vault Active), but
/// downstream browse and intelligence code must always receive one row per physical song path.
public enum SongCatalogDeduplicator {
    public static func uniqueByID(_ songs: [Song]) -> [Song] {
        var seen: Set<String> = []
        return songs.filter { seen.insert($0.id).inserted }
    }
}
