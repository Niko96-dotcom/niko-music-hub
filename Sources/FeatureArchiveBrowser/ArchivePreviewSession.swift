import AppCore
import Combine
import NikoMusicCore
import Foundation

/// App-lifetime playback; song selection and preview defaults are independent.
@MainActor
final class ArchivePreviewSession: ObservableObject {
    static let shared = ArchivePreviewSession()
    let player: ArchivePreviewPlayer
    @Published private(set) var songID: String?
    @Published private(set) var songTitle = ""
    @Published private(set) var preview: PreviewCandidate?
    @Published var volume = 0.8 {
        didSet { player.setVolume(volume) }
    }
    @Published private(set) var captureActive = false
    private var observations: Set<AnyCancellable> = []
    private var openSongAction: (() -> Void)?

    init(player: ArchivePreviewPlayer = ArchivePreviewPlayer(), capture: AudioCaptureActivity = .shared) {
        self.player = player
        player.setVolume(volume)
        player.$playbackIntentActive.removeDuplicates().sink { [weak self] playing in
            self?.isPlaying = playing
        }.store(in: &observations)
        ArchivePlaybackCoordinator.shared.$stopGeneration.dropFirst().sink { [weak self] _ in
            self?.clear()
        }.store(in: &observations)
        capture.$isActive.sink { [weak self] active in
            self?.captureActive = active
            if active { self?.player.pause() }
        }.store(in: &observations)
    }

    @Published private(set) var isPlaying = false

    func audition(song: Song, candidate: PreviewCandidate? = nil, openSong: @escaping () -> Void) {
        guard !captureActive, let candidate = candidate ?? song.previewCandidates.first(where: { $0.id == song.mainPreviewCandidateID }) else { return }
        if songID == song.id, preview?.id == candidate.id, preview?.modifiedAt == candidate.modifiedAt, player.playbackError == nil {
            toggle()
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
        guard !captureActive, let preview else { return }
        if player.playbackError != nil { player.load(url: preview.filePath) }
        else { player.toggle(at: preview.filePath) }
    }

    func openSong() { openSongAction?() }

    func clear() {
        player.forceStop()
        songID = nil
        songTitle = ""
        preview = nil
        openSongAction = nil
    }
}

extension ArchiveBrowserViewModel {
    func audition(_ song: Song, candidate: PreviewCandidate? = nil) {
        ArchivePreviewSession.shared.audition(song: song, candidate: candidate) { [weak self] in
            guard let self, let current = self.songs.first(where: { $0.id == song.id }) else { return }
            self.selectSong(current)
            self.viewMode = .boardDetail
        }
    }
}
