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
    func testTogglePlayPauseRequestBumpsGenerationAndCarriesURL() {
        let coordinator = ArchivePlaybackCoordinator.shared
        let before = coordinator.togglePlayPauseGeneration
        let url = URL(fileURLWithPath: "/tmp/track/mix.wav")

        coordinator.requestTogglePlayPause(for: url)

        XCTAssertEqual(coordinator.togglePlayPauseGeneration, before &+ 1)
        XCTAssertEqual(coordinator.togglePlayPauseURL, url)
    }
}
