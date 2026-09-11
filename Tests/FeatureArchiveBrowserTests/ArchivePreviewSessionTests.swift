import AppCore
import AVFoundation
import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

@MainActor
final class ArchivePreviewSessionTests: XCTestCase {
    func testComparisonPreservesPausedTimeAndClampsShorterFile() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = ArchivePreviewSession(capture: AudioCaptureActivity())
        defer { session.clear() }
        session.audition(song: fixture.song, openSong: {})
        session.player.pause()
        try await ready(session.player)
        session.player.seek(to: 2, url: fixture.previews[0].filePath)
        session.compare(song: fixture.song, candidate: fixture.previews[1])
        try await ready(session.player)
        XCTAssertFalse(session.isPlaying)
        XCTAssertEqual(session.player.currentTime, 2, accuracy: 0.15)
        session.compare(song: fixture.song, candidate: fixture.previews[2])
        try await ready(session.player)
        XCTAssertFalse(session.isPlaying)
        XCTAssertEqual(session.player.duration, 1, accuracy: 0.1)
        XCTAssertEqual(session.player.currentTime, 1, accuracy: 0.15)
    }

    func testNavigationAndPreviewDefaultDoNotReplaceLoadedTrack() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = ArchiveBrowserViewModel(context: TestToolContext.make())
        model.songs = [fixture.song]
        model.filteredSongs = [fixture.song]
        let session = ArchivePreviewSession.shared
        defer { session.clear() }
        model.audition(fixture.song)
        session.player.pause()
        try await ready(session.player)
        session.player.seek(to: 1, url: fixture.previews[0].filePath)
        let other = Song(folderPath: fixture.root.appendingPathComponent("other"), originalFolderName: "Other", displayTitle: "Other")
        model.selectSong(other)
        model.reconcileSelectedSong()
        XCTAssertNil(model.selectedSong)
        XCTAssertEqual(session.preview?.id, fixture.previews[0].id, "Removing a different selected song must not clear loaded audio")
        model.selectSongOnBoard(fixture.song)
        model.viewMode = .list
        model.clearSelection(stopPlayback: false)
        XCTAssertEqual(session.preview?.id, fixture.previews[0].id)
        XCTAssertEqual(session.player.currentTime, 1, accuracy: 0.1)
        XCTAssertFalse(session.isPlaying)
        // A metadata update does not call the playback engine.
        var changed = fixture.song
        changed.mainPreviewCandidateID = fixture.previews[1].id
        model.songs = [changed]
        XCTAssertEqual(session.preview?.id, fixture.previews[0].id)
        ArchivePreviewPlayback.stopAll()
        XCTAssertNil(session.preview, "A lifecycle reset clears paused audio too")
    }

    func testCapturePausesPendingPlaybackBlocksAuditionAndDoesNotResume() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let capture = AudioCaptureActivity()
        let session = ArchivePreviewSession(capture: capture)
        defer { session.clear() }
        session.audition(song: fixture.song, openSong: {})
        let owner = UUID()
        capture.setActive(true, owner: owner)
        try await ready(session.player)
        XCTAssertFalse(session.isPlaying)
        session.toggle()
        session.compare(song: fixture.song, candidate: fixture.previews[1])
        XCTAssertFalse(session.isPlaying)
        XCTAssertEqual(session.preview?.id, fixture.previews[0].id)
        capture.setActive(false, owner: owner)
        XCTAssertFalse(session.isPlaying)
    }

    func testRapidReplacementAndFailureCannotReviveOldRequest() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = ArchivePreviewSession(capture: AudioCaptureActivity())
        defer { session.clear() }
        session.audition(song: fixture.song, openSong: {})
        session.audition(song: fixture.song, candidate: fixture.previews[1], openSong: {})
        session.player.pause()
        try await ready(session.player)
        XCTAssertEqual(session.player.activeURL, fixture.previews[1].filePath)
        XCTAssertFalse(session.isPlaying)
        let missing = PreviewCandidate(filePath: fixture.root.appendingPathComponent("missing.wav"), fileName: "missing.wav", folderRole: .mixdown, modifiedAt: Date(), detectedRole: .mainMix)
        session.audition(song: fixture.song, candidate: missing, openSong: {})
        let deadline = Date().addingTimeInterval(5)
        while session.player.playbackError == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(session.player.playbackError)
        XCTAssertFalse(session.isPlaying)
        session.audition(song: fixture.song, candidate: fixture.previews[0], openSong: {})
        session.player.pause()
        try await ready(session.player)
        XCTAssertNil(session.player.playbackError)
        XCTAssertEqual(session.preview?.id, fixture.previews[0].id)
    }

    private func ready(_ player: ArchivePreviewPlayer) async throws {
        let deadline = Date().addingTimeInterval(6)
        while player.isLoading, player.playbackError == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(player.playbackError)
        XCTAssertFalse(player.isLoading)
    }

    private func makeFixture() throws -> (root: URL, song: Song, previews: [PreviewCandidate]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NMHPreview-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previews = try [3, 3, 1].enumerated().map { index, seconds in
            let url = root.appendingPathComponent("mix-\(index).wav")
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 8000)))
            buffer.frameLength = buffer.frameCapacity
            if let samples = buffer.floatChannelData?[0] { samples.initialize(repeating: 0, count: Int(buffer.frameLength)) }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return PreviewCandidate(filePath: url, fileName: url.lastPathComponent, folderRole: .mixdown, modifiedAt: Date(), detectedRole: .mainMix)
        }
        return (root, Song(folderPath: root, originalFolderName: "Fixture", displayTitle: "Fixture", previewCandidates: previews, mainPreviewCandidateID: previews[0].id), previews)
    }
}
