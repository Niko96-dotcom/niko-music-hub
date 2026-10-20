import Foundation

/// What the stored song rows of the archive index hold, as values.
///
/// A save used to encode every song to JSON only to let SQLite throw away the rows that came out equal. For a
/// catalog of 10,000 songs that is about 110 MB of text, built and freed after every scan and every edit.
/// Remembering the songs the rows hold lets a save encode just the songs that differ. The memo lives on the
/// database object because every store over the same connection shares the same rows.
///
/// The entry is trusted only while nothing else wrote the rows: another save replaces or invalidates it (the
/// generation moves), and a write from another connection changes `PRAGMA data_version` (checked by the store).
final class SnapshotRowsMemo: @unchecked Sendable {
    struct Entry: Sendable {
        let songs: [Song]
        let dataVersion: Int64
        let generation: UInt64
    }

    private let lock = NSLock()
    private var entry: Entry?
    private var counter: UInt64 = 0

    /// Moves on every `replace` and `invalidate`.
    var generation: UInt64 { lock.withLock { counter } }

    func current() -> Entry? { lock.withLock { entry } }

    func replace(songs: [Song], dataVersion: Int64) {
        lock.withLock {
            counter &+= 1
            entry = Entry(songs: songs, dataVersion: dataVersion, generation: counter)
        }
    }

    /// Records the songs only if the memo did not change since `generation` was read: a load must not
    /// overwrite what a save recorded while the load was decoding.
    func replace(songs: [Song], dataVersion: Int64, ifGeneration expected: UInt64) {
        lock.withLock {
            guard counter == expected else { return }
            counter &+= 1
            entry = Entry(songs: songs, dataVersion: dataVersion, generation: counter)
        }
    }

    func invalidate() {
        lock.withLock {
            counter &+= 1
            entry = nil
        }
    }
}

/// Which song rows a save has to write, given the songs the rows are known to hold.
struct SongRowDiff {
    /// Indices into the new songs of songs that are new or differ from the known song with the same id.
    let changedIndices: [Int]
    /// Indices of songs equal to their known song that moved to another position.
    let movedIndices: [Int]
    /// Ids of known songs that are no longer present.
    let removedIDs: [String]

    /// Nil when an id repeats on either side: the rows are keyed by id, so repeats cannot be diffed.
    init?(known: [Song], next: [Song]) {
        guard let knownIndex = Self.positions(of: known), let nextPositions = Self.positions(of: next) else { return nil }
        // Equal songs that do not share storage (a rescan result) compare field by field, so the verdicts
        // come from several cores.
        let verdicts: [UInt8] = ParallelMap.map(Array(next.indices)) { index in
            let song = next[index]
            guard let old = knownIndex[song.id], known[old] == song else { return 1 }
            return old == index ? 0 : 2
        }
        var changed: [Int] = []
        var moved: [Int] = []
        for (index, verdict) in verdicts.enumerated() {
            if verdict == 1 { changed.append(index) } else if verdict == 2 { moved.append(index) }
        }
        changedIndices = changed
        movedIndices = moved
        removedIDs = known.map(\.id).filter { nextPositions[$0] == nil }
    }

    /// Position of each song by id; nil when an id repeats.
    private static func positions(of songs: [Song]) -> [String: Int]? {
        var positions: [String: Int] = [:]
        positions.reserveCapacity(songs.count)
        for (index, song) in songs.enumerated() {
            guard positions.updateValue(index, forKey: song.id) == nil else { return nil }
        }
        return positions
    }
}
