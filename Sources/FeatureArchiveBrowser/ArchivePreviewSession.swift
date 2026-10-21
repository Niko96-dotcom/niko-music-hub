import AppCore
import Combine
import NikoMusicCore
import Foundation

/// App-lifetime playback. Active audio survives browsing; the paused transport follows selection.
@MainActor
final class ArchivePreviewSession: ObservableObject {
    static let shared = ArchivePreviewSession()
    let player: ArchivePreviewPlayer
    @Published private(set) var songID: String? {
        didSet {
            // NMH-042: playback song change changes layout context.
            if oldValue != songID {
                HubAccessibilityAnnouncer.layoutChanged()
            }
        }
    }
    @Published private(set) var songTitle = ""
    @Published private(set) var preview: PreviewCandidate?
    @Published var volume = 0.8 {
        didSet { player.setVolume(volume) }
    }
    @Published private(set) var captureActive = false
    private var observations: Set<AnyCancellable> = []
    /// NMH-137: pauses preview on headphone unplug; never clears the session.
    /// Hide (Cmd-H) keeps playing; capture pause below (NMH-116) is unchanged.
    private(set) var routeObserver: ArchivePreviewRouteObserver?
    private var openSongAction: (() -> Void)?
    private var selectedSong: Song?
    private var selectedSongAction: (() -> Void)?

    init(player: ArchivePreviewPlayer = ArchivePreviewPlayer(), capture: AudioCaptureActivity = .shared) {
        self.player = player
        player.setVolume(volume)
        player.$playbackIntentActive.removeDuplicates().sink { [weak self] playing in
            self?.isPlaying = playing
            if !playing {
                // @Published emits before the player finishes pausing/stopping. Reconcile
                // after that operation, never halfway through an explicit load or compare.
                Task { @MainActor [weak self] in self?.followSelectionIfIdle() }
            }
        }.store(in: &observations)
        ArchivePlaybackCoordinator.shared.$stopGeneration.dropFirst().sink { [weak self] _ in
            self?.clear()
        }.store(in: &observations)
        capture.$isActive.sink { [weak self] active in
            self?.captureActive = active
            if active { self?.player.pause() }
            else { self?.followSelectionIfIdle() }
        }.store(in: &observations)
        // NMH-137: observe output-route changes once. Pause on unplug only.
        self.routeObserver = ArchivePreviewRouteObserver.start(pausing: player)
    }

    @Published private(set) var isPlaying = false

    func followSelection(_ song: Song?, openSong: @escaping () -> Void) {
        selectedSong = song
        selectedSongAction = song == nil ? nil : openSong
        followSelectionIfIdle()
    }

    private func followSelectionIfIdle() {
        guard !captureActive, !player.playbackIntentActive, let selectedSong else { return }
        if songID == selectedSong.id, let preview,
           selectedSong.previewCandidates.contains(where: { $0.id == preview.id && $0.modifiedAt == preview.modifiedAt }) {
            // Keep a valid explicit alternate and its paused position. Metadata/rescans
            // can still refresh the title or remove/replace the loaded file.
            songTitle = selectedSong.effectiveDisplayTitle
            openSongAction = selectedSongAction
            return
        }
        guard let candidate = selectedSong.previewCandidates.first(where: { $0.id == selectedSong.mainPreviewCandidateID }) else {
            clearLoadedPreview()
            return
        }
        songID = selectedSong.id
        songTitle = selectedSong.effectiveDisplayTitle
        preview = candidate
        openSongAction = selectedSongAction
        // Selection only binds a URL; it never starts audio or allocates AVPlayer.
        player.forceStop()
        player.bind(url: candidate.filePath)
    }

    func audition(song: Song, candidate: PreviewCandidate? = nil, openSong: @escaping () -> Void) {
        guard !captureActive, let candidate = candidate ?? song.previewCandidates.first(where: { $0.id == song.mainPreviewCandidateID }) else { return }
        if songID == song.id, preview?.id == candidate.id, preview?.modifiedAt == candidate.modifiedAt, player.playbackError == nil {
            toggleLoaded()
            return
        }
        songID = song.id
        songTitle = song.effectiveDisplayTitle
        preview = candidate
        openSongAction = openSong
        player.load(url: candidate.filePath)
    }

    /// Explicit elapsed-time comparison. Alignment is a user decision: edits and
    /// tempo changes can put different musical moments at the same timestamp.
    func compare(song: Song, candidate: PreviewCandidate) {
        guard !captureActive, songID == song.id, preview?.id != candidate.id else { return }
        let position = player.currentTime
        let playing = isPlaying
        preview = candidate
        player.load(url: candidate.filePath, position: position, autoplay: playing)
    }

    func toggle() {
        followSelectionIfIdle()
        toggleLoaded()
    }

    private func toggleLoaded() {
        guard !captureActive, let preview else { return }
        if player.playbackError != nil { player.load(url: preview.filePath) }
        else { player.toggle(at: preview.filePath) }
    }

    func openSong() { openSongAction?() }

    func clear() {
        selectedSong = nil
        selectedSongAction = nil
        clearLoadedPreview()
    }

    private func clearLoadedPreview() {
        player.bind(url: nil)
        songID = nil
        songTitle = ""
        preview = nil
        openSongAction = nil
    }
}

extension ArchiveBrowserViewModel {
    func synchronizePreviewSelection() {
        let songID = selectedSong?.id
        ArchivePreviewSession.shared.followSelection(selectedSong) { [weak self] in
            guard let self, let song = self.songs.first(where: { $0.id == songID }) else { return }
            self.openSongDetail(song)
        }
    }

    func audition(_ song: Song, candidate: PreviewCandidate? = nil) {
        ArchivePreviewSession.shared.audition(song: song, candidate: candidate) { [weak self] in
            guard let self, let current = self.songs.first(where: { $0.id == song.id }) else { return }
            self.selectSong(current)
            self.viewMode = .boardDetail
        }
    }
}
