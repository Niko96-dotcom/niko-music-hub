import Combine
import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

final class ArchiveBoardPlaybackTests: XCTestCase {
    func testSongMainPreviewURLResolvesSelectedCandidate() {
        let folder = URL(fileURLWithPath: "/tmp/track", isDirectory: true)
        let preview = PreviewCandidate(
            filePath: folder.appendingPathComponent("mix.wav"),
            fileName: "mix.wav",
            folderRole: .mixdown,
            modifiedAt: Date(timeIntervalSince1970: 1_000),
            detectedRole: .mainMix
        )
        var song = Song(
            folderPath: folder,
            originalFolderName: "Track",
            displayTitle: "Track",
            previewCandidates: [preview],
            mainPreviewCandidateID: preview.id
        )
        XCTAssertEqual(song.mainPreviewURL, preview.filePath)

        song.mainPreviewCandidateID = nil
        XCTAssertNil(song.mainPreviewURL)
    }

    @MainActor
    func testGlobalStopDoesNotBroadcastWhenNoPreviewIsAudible() {
        let coordinator = ArchivePlaybackCoordinator.shared
        if let activeURL = coordinator.activeURL {
            coordinator.endPlayback(for: activeURL)
        }
        let generation = coordinator.stopGeneration
        var broadcasts = 0
        let observation = coordinator.$stopGeneration
            .dropFirst()
            .sink { _ in broadcasts += 1 }

        coordinator.stopAllPlayback()

        XCTAssertNil(coordinator.activeURL)
        XCTAssertEqual(coordinator.stopGeneration, generation)
        XCTAssertEqual(broadcasts, 0)
        observation.cancel()
    }

    @MainActor
    func testForceStopKeepsLazyBoundRowUntouched() {
        let model = ArchivePreviewPlayer()
        let url = URL(fileURLWithPath: "/tmp/track/lazy-bound.wav")
        model.bind(url: url)

        var publications = 0
        let observation = model.objectWillChange.sink { _ in publications += 1 }

        model.forceStop()

        XCTAssertEqual(model.activeURL, url)
        XCTAssertEqual(model.currentTime, 0)
        XCTAssertEqual(model.duration, 0)
        XCTAssertNil(model.hookTime)
        XCTAssertEqual(publications, 0)
        observation.cancel()
    }

    @MainActor
    func testGlobalStopBroadcastTearsDownPreparedAudiblePlayer() {
        let coordinator = ArchivePlaybackCoordinator.shared
        if let activeURL = coordinator.activeURL {
            coordinator.endPlayback(for: activeURL)
        }

        let model = ArchivePreviewPlayer()
        let url = URL(fileURLWithPath: "/tmp/track/prepared.wav")
        model.prepare(url: url)
        coordinator.beginPlayback(for: url)

        let generation = coordinator.stopGeneration
        var broadcasts = 0
        let observation = coordinator.$stopGeneration
            .dropFirst()
            .sink { _ in broadcasts += 1 }

        coordinator.stopAllPlayback()
        // This mirrors the mounted player reacting to the coordinator broadcast.
        model.forceStop()

        XCTAssertNil(coordinator.activeURL)
        XCTAssertEqual(coordinator.stopGeneration, generation &+ 1)
        XCTAssertEqual(broadcasts, 1)
        XCTAssertNil(model.activeURL)
        XCTAssertEqual(model.currentTime, 0)
        XCTAssertEqual(model.duration, 0)
        XCTAssertNil(model.hookTime)
        observation.cancel()
    }
}
