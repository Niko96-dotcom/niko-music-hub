import XCTest
@testable import NikoMusicCore

/// Indexing, syncing and matching run on several cores for large catalogs. Over a catalog far past the
/// parallel threshold they must return exactly what a one-song-at-a-time pass returns.
final class MusicSearchParallelismTests: XCTestCase {
    private func makeCatalog(count: Int) -> [Song] {
        let adjectives = ["Amber", "Neon", "Velvet", "Hollow", "Golden", "Silent", "Electric", "Paper"]
        let nouns = ["Moth", "Hook", "Tide", "Signal", "Harbor", "Engine", "Garden", "Mirror"]
        return (0..<count).map { index in
            let title = "\(adjectives[index % 8]) \(nouns[(index / 8) % 8]) \(index)"
            return Song(
                folderPath: URL(fileURLWithPath: "/parallel-search/\(title)", isDirectory: true),
                originalFolderName: title, displayTitle: title,
                aliases: index % 11 == 0 ? ["Demo \(index)"] : [],
                appNote: index % 13 == 0 ? "note about \(nouns[index % 8])" : nil,
                collaboratorNames: index % 9 == 0 ? ["Maria Klein"] : [],
                workflowStatus: index % 5 == 0 ? .song : nil
            )
        }
    }

    /// The straightforward one-song-at-a-time search, written against the matcher directly.
    private func serialSearch(_ songs: [Song], _ query: String) -> [MusicSearchResult] {
        let tokens = MusicSearchMatcher.tokens(from: query)
        let scored = songs.compactMap { song -> (MusicSearchResult, MusicSearchMatchTier)? in
            let details = MusicSearchMatcher.matchDetails(song: song, queryTokens: tokens)
            let score = details.reduce(0) { $0 + $1.score }
            guard score > 0 else { return nil }
            return (MusicSearchResult(song: song, score: score, details: details), details.map(\.kind.tier).max() ?? .primary)
        }
        guard let best = scored.map(\.1).min() else { return [] }
        return scored.filter { $0.1 == best }.map(\.0).sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.song.effectiveDisplayTitle.localizedCaseInsensitiveCompare(rhs.song.effectiveDisplayTitle) == .orderedAscending
        }
    }

    func testLargeCatalogSearchMatchesTheSerialPass() {
        let songs = makeCatalog(count: 1_500)
        let index = MusicSearchIndex(songs: songs)
        for query in ["neon", "amber hook", "maria", "demo 11", "nion hok", "song", "zzzz absent", "velvet signal 100"] {
            let parallel = index.searchResults(query)
            let reference = serialSearch(songs, query)
            XCTAssertEqual(parallel.map(\.song.id), reference.map(\.song.id), query)
            XCTAssertEqual(parallel.map(\.score), reference.map(\.score), query)
            XCTAssertEqual(parallel.map(\.matchSummary), reference.map(\.matchSummary), query)
        }
    }

    func testLargeCatalogSyncMatchesAFreshIndexAfterEdits() {
        var songs = makeCatalog(count: 1_500)
        var synced = MusicSearchIndex(songs: songs)
        songs[10].aliases = ["renamed alias"]
        songs[700].displayTitle = "Completely New Title"
        songs[1_200].scanWarnings = ["cannot read stems"]
        songs.remove(at: 5)
        songs.append(makeCatalog(count: 1_501).last!)
        synced.sync(from: songs)
        let fresh = MusicSearchIndex(songs: songs)
        for query in ["renamed", "completely", "stems", "neon", "1500"] {
            XCTAssertEqual(synced.searchResults(query).map(\.song.id), fresh.searchResults(query).map(\.song.id), query)
            XCTAssertEqual(synced.searchResults(query).map(\.score), fresh.searchResults(query).map(\.score), query)
        }
        XCTAssertEqual(synced.songs, songs)
    }
}
