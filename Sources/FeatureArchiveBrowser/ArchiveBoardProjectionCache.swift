import Combine
import NikoMusicCore

/// View-owned cache for the board's expensive status-column projection.
///
/// `ArchiveBrowserViewModel` publishes selection changes alongside browse
/// changes. The board listens to `filteredSongs` specifically, so selecting a
/// card never filters or sorts the full catalog again.
@MainActor
final class ArchiveBoardProjectionCache: ObservableObject {
    @Published private(set) var columns: [ArchiveBoardColumn]

    private var cachedPreservingOrder: Bool
    private var cachedSongs: [Song]
    private(set) var projectionGeneration: UInt64 = 0

    init(songs: [Song], preservingOrder: Bool = false) {
        cachedPreservingOrder = preservingOrder
        cachedSongs = songs
        columns = ArchiveBoardProjection.columns(from: songs, preservingOrder: preservingOrder)
        projectionGeneration = 1
    }

    /// Rebuild only when the browse projection actually changed. The cached
    /// input is an array value, so its copy-on-write storage is shared with
    /// the view model until one side changes it.
    @discardableResult
    func refresh(with songs: [Song], preservingOrder: Bool = false) -> Bool {
        guard !songs.equalsConcurrently(cachedSongs) || preservingOrder != cachedPreservingOrder else { return false }

        cachedPreservingOrder = preservingOrder
        cachedSongs = songs
        // A column that did not change keeps its previous value (and array storage): every later
        // comparison of it by SwiftUI is then a same-storage check instead of a walk over its songs.
        let previous = Dictionary(columns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        columns = ArchiveBoardProjection.columns(from: songs, preservingOrder: preservingOrder).map { next in
            if let old = previous[next.id], old == next { return old }
            return next
        }
        projectionGeneration &+= 1
        return true
    }
}
