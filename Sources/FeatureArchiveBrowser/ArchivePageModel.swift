import AppCore
import Combine
import Foundation
import NikoMusicCore

/// Archive page layout: the board is home, opening a card goes to
/// fullscreen detail, and the classic sidebar+detail list stays reachable.
enum ArchiveViewMode {
    case board
    case boardDetail
    case list
    case analytics
}

/// The archive page: which page shows (`viewMode`, the compact list's
/// `listShowsDetail`), which song is selected, the song detail's two
/// disclosures, and the analytics snapshot on screen.
///
/// Rules it owns:
///
/// - Views state intent; only this type writes `viewMode` and
///   `listShowsDetail` (their setters are private, and
///   `ArchiveViewIntentSourceTests` names this file as the one writer).
/// - Selecting a song collapses the detail's disclosures, so a new song opens
///   on a calm first viewport.
/// - The page's route (`navigationRoute`) is what the shell's back/forward
///   records; board selection is not part of it. A restored route whose song is
///   gone falls back to its page without the song.
/// - A detail page whose song disappeared shows the board under it
///   (`showsBoardPage`), so board-only commands and visibility agree.
///
/// Every write of `selectedSong` reaches `selectionDidChange`, which the view
/// model uses for the preview session and the nearby open error.
/// `ArchiveBrowserViewModel` holds this model and forwards its publishes.
@MainActor
final class ArchivePageModel: ObservableObject {
    @Published private(set) var viewMode: ArchiveViewMode = .board {
        didSet {
            // NMH-042: board ↔ list ↔ boardDetail ↔ analytics changes layout.
            if oldValue != viewMode {
                HubAccessibilityAnnouncer.layoutChanged()
            }
        }
    }
    /// Compact list shows the detail page only after an explicit open (double-click / Return).
    @Published private(set) var listShowsDetail = false
    @Published private(set) var selectedSong: Song? {
        didSet { selectionDidChange(oldValue?.id) }
    }
    /// Song-detail "Details" disclosure state — hoisted so the browser-level "d"
    /// keyboard shortcut can toggle it.
    @Published var songDetailsExpanded = false
    @Published var pluginsSectionExpanded = false
    @Published private(set) var analyticsSnapshot: ArchiveAnalyticsSnapshot?

    /// Called after every write of `selectedSong`, with the previous song's id.
    private let selectionDidChange: @MainActor (_ previousSongID: String?) -> Void
    private var navigationCancellable: AnyCancellable?

    init(selectionDidChange: @escaping @MainActor (_ previousSongID: String?) -> Void) {
        self.selectionDidChange = selectionDidChange
    }

    // MARK: - Selection

    /// Selects a song and collapses the detail's disclosures (ARCH-07).
    func select(_ song: Song) {
        selectedSong = song
        if songDetailsExpanded {
            songDetailsExpanded = false
        }
        if pluginsSectionExpanded {
            pluginsSectionExpanded = false
        }
    }

    /// The live catalog's newer value of the selected song, so the detail never
    /// shows a stale project or preview. Writes only when the value changed.
    func refreshSelection(to fresh: Song) {
        if fresh != selectedSong {
            selectedSong = fresh
        }
    }

    /// No song selected: the compact list leaves its detail and the
    /// disclosures collapse.
    func clearSelection() {
        selectedSong = nil
        listShowsDetail = false
        songDetailsExpanded = false
        pluginsSectionExpanded = false
    }

    /// A root change: no song is selected. The page and the list detail flag stay.
    func clearForRootChange() {
        selectedSong = nil
        songDetailsExpanded = false
        pluginsSectionExpanded = false
    }

    /// Where an arrow key moves the highlight: through the list in list order, on
    /// the board by lane. Detail and analytics take no arrow moves.
    func keyboardMoveTarget(
        _ direction: ArchiveSongMoveDirection,
        in filteredSongs: [Song],
        isSearching: Bool
    ) -> Song? {
        switch viewMode {
        case .list:
            return ArchiveSongSelectionNavigator.move(
                direction: direction,
                songs: filteredSongs,
                selectedID: selectedSong?.id
            )
        case .board:
            return ArchiveSongSelectionNavigator.moveOnBoard(
                direction: direction,
                songs: filteredSongs,
                selectedID: selectedSong?.id,
                preservingOrder: isSearching
            )
        case .boardDetail, .analytics:
            return nil
        }
    }

    /// The selected song a diagnostics export describes.
    func selectedSongExportContext() -> ArchiveDiagnosticsSelectedSongContext? {
        selectedSong.map(ArchiveDiagnosticsSelectedSongContext.from(song:))
    }

    // MARK: - Pages

    /// Opens the selected song's detail: the board goes to fullscreen detail, the
    /// list shows its detail column, analytics stays.
    func openDetail() {
        switch viewMode {
        case .board, .boardDetail:
            viewMode = .boardDetail
        case .list:
            listShowsDetail = true
        case .analytics:
            break
        }
    }

    /// The fullscreen detail of the selected song, from any page (the preview
    /// bar's Open action).
    func showBoardDetail() {
        viewMode = .boardDetail
    }

    /// Back to the board from its detail or from analytics. The selection stays,
    /// so the board highlights the song the person came from.
    func showBoard() {
        viewMode = .board
    }

    /// Switches between the board and the classic list without disturbing
    /// the selection; detail/analytics fold back to their parent board.
    func setBrowseLayout(list: Bool) {
        if list {
            viewMode = .list
        } else {
            viewMode = selectedSong != nil && viewMode == .boardDetail ? .boardDetail : .board
        }
    }

    func showAnalytics(_ snapshot: ArchiveAnalyticsSnapshot) {
        analyticsSnapshot = snapshot
        viewMode = .analytics
    }

    /// A newer snapshot for the analytics page (a scan or status edit landed).
    func updateAnalytics(_ snapshot: ArchiveAnalyticsSnapshot) {
        analyticsSnapshot = snapshot
    }

    var isListLayout: Bool { viewMode == .list }

    /// A disappearing selection leaves the existing detail route on its board
    /// fallback. Visibility and board-only commands must agree on that page.
    var showsBoardPage: Bool {
        viewMode == .board || (viewMode == .boardDetail && selectedSong == nil)
    }

    // MARK: - Navigation history

    /// Route token for the current page. Board selection (highlight only)
    /// is deliberately not part of the route.
    var navigationRoute: String {
        Self.navigationRoute(viewMode: viewMode, songID: selectedSong?.id)
    }

    static func navigationRoute(viewMode: ArchiveViewMode, songID: String?) -> String {
        switch viewMode {
        case .board: return "board"
        case .analytics: return "analytics"
        case .boardDetail: return "detail:" + (songID ?? "")
        case .list: return songID.map { "list:" + $0 } ?? "list"
        }
    }

    /// Records every page change in the shell's history and lets it put the page
    /// back (`restore`).
    func attach(
        _ history: HubNavigationHistory,
        restore: @escaping @MainActor (_ route: String?) -> Void
    ) {
        history.registerRestorer(for: .archiveBrowser) { route in
            restore(route)
        }
        history.noteRoute(toolID: .archiveBrowser, route: navigationRoute)
        // @Published emits on willSet, so build the route from the emitted values
        // (not `self`) and stay synchronous so restore-time suppression applies.
        navigationCancellable = Publishers.CombineLatest($viewMode, $selectedSong.map { $0?.id })
            .dropFirst()
            .sink { viewMode, songID in
                history.record(toolID: .archiveBrowser, route: Self.navigationRoute(viewMode: viewMode, songID: songID))
            }
    }

    /// Puts the page back on a recorded route. `song` finds a catalog song by id;
    /// `analytics` builds a fresh snapshot for the analytics page.
    func restore(
        route: String?,
        song: (String) -> Song?,
        analytics: () -> ArchiveAnalyticsSnapshot
    ) {
        guard let route else { viewMode = .board; return }
        let parts = route.split(separator: ":", maxSplits: 1).map(String.init)
        let routeSong = parts.count > 1 ? song(parts[1]) : nil
        switch parts.first {
        case "detail":
            if let routeSong {
                selectedSong = routeSong
                viewMode = .boardDetail
            } else {
                viewMode = .board
            }
        case "list":
            selectedSong = routeSong
            viewMode = .list
        case "analytics":
            showAnalytics(analytics())
        default:
            viewMode = .board
        }
    }
}
