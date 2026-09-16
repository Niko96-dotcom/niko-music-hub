import AppCore
import AVFoundation
import Foundation
import NikoMusicCore
import XCTest
@testable import FeatureArchiveBrowser

/// NMH-137: headphone unplug pauses preview without clearing the persistent session.
/// Hardware unplug and Cmd-H hide remain `runtime only`; this covers the testable hook.
@MainActor
final class ArchivePreviewRouteObserverTests: XCTestCase {
    func testOldDeviceUnavailablePausesWithoutClearingSession() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = ArchivePreviewSession(capture: AudioCaptureActivity())
        defer { session.clear() }
        XCTAssertNotNil(session.routeObserver, "Session must start the route observer (NMH-137 wiring)")
        session.audition(song: fixture.song, openSong: {})
        try await ready(session.player)
        XCTAssertTrue(session.isPlaying, "Precondition: fixture preview is playing before the route change")
        session.routeObserver?.handleRouteChange(.oldDeviceUnavailable)
        XCTAssertFalse(session.isPlaying)
        XCTAssertFalse(session.player.playbackIntentActive)
        XCTAssertNotNil(session.preview, "Unplug pauses; it must not clear the persistent session")
        XCTAssertEqual(session.preview?.id, fixture.previews[0].id)
    }

    func testOtherRouteChangeKeepsPlaying() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = ArchivePreviewSession(capture: AudioCaptureActivity())
        defer { session.clear() }
        session.audition(song: fixture.song, openSong: {})
        try await ready(session.player)
        XCTAssertTrue(session.isPlaying, "Precondition: fixture preview is playing before the route change")
        session.routeObserver?.handleRouteChange(.other)
        XCTAssertTrue(session.isPlaying, "Unrelated route events must not pause playback")
        XCTAssertNotNil(session.preview)
    }

    private func ready(_ player: ArchivePreviewPlayer) async throws {
        let deadline = Date().addingTimeInterval(6)
        while player.isLoading, player.playbackError == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(player.playbackError)
        XCTAssertFalse(player.isLoading)
    }

    private func makeFixture() throws -> (root: URL, song: Song, previews: [PreviewCandidate]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NMHRoute-\(UUID())")
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
