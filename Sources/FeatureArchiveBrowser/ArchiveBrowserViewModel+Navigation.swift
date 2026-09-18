import AppCore
import Combine
import Foundation
import NikoMusicCore

/// Shell back/forward integration: the archive reports its page as an
/// opaque route and can put itself back on one.
extension ArchiveBrowserViewModel {
    static let navigationToolID = ToolFeatureID("archive-browser")

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

    func attachNavigationHistory(_ history: HubNavigationHistory) {
        history.registerRestorer(for: Self.navigationToolID) { [weak self] route in
            self?.restoreNavigationRoute(route)
        }
        history.noteRoute(toolID: Self.navigationToolID, route: navigationRoute)
        // @Published emits on willSet, so build the route from the emitted values
        // (not `self`) and stay synchronous so restore-time suppression applies.
        navigationCancellable = Publishers.CombineLatest($viewMode, $selectedSong.map { $0?.id })
            .dropFirst()
            .sink { viewMode, songID in
                history.record(toolID: Self.navigationToolID, route: Self.navigationRoute(viewMode: viewMode, songID: songID))
            }
    }

    func restoreNavigationRoute(_ route: String?) {
        guard let route else { viewMode = .board; return }
        let parts = route.split(separator: ":", maxSplits: 1).map(String.init)
        let songID = parts.count > 1 ? parts[1] : nil
        let song = songID.flatMap { id in songs.first(where: { $0.id == id }) }
        switch parts.first {
        case "detail":
            if let song {
                selectedSong = song
                viewMode = .boardDetail
            } else {
                viewMode = .board
            }
        case "list":
            selectedSong = song
            viewMode = .list
        case "analytics":
            refreshAnalytics()
            viewMode = .analytics
        default:
            viewMode = .board
        }
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

    var isListLayout: Bool { viewMode == .list }
}
