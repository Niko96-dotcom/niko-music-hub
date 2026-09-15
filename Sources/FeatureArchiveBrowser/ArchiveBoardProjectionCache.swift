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
        guard songs != cachedSongs || preservingOrder != cachedPreservingOrder else { return false }

        cachedPreservingOrder = preservingOrder
        cachedSongs = songs
        columns = ArchiveBoardProjection.columns(from: songs, preservingOrder: preservingOrder)
        projectionGeneration &+= 1
        return true
    }
}
