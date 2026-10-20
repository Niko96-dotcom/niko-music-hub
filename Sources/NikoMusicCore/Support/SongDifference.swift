import Foundation

extension Array where Element == Song {
    /// The songs that differ from the song with the same id in `held`, or that `held` does not contain,
    /// in their original order.
    ///
    /// A rescan hands back every song of the catalog, nearly all of them equal to what is already held; what has to
    /// react to a changed song (analysis caches, plugin summaries) only needs the few that are not. Songs that
    /// share storage with the held one are equal without a field-by-field comparison, and the rest compare on several
    /// cores (`ParallelMap`).
    public func songsDiffering(from held: [String: Song]) -> [Song] {
        let differs: [Bool] = ParallelMap.map(self) { song in held[song.id] != song }
        return zip(self, differs).compactMap { $1 ? $0 : nil }
    }
}
