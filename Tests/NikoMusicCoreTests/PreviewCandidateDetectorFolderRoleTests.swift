import XCTest
@testable import NikoMusicCore

final class PreviewCandidateDetectorFolderRoleTests: XCTestCase {
    private let songFolder = URL(fileURLWithPath: "/Volumes/Music/Songs/Neon Hook", isDirectory: true)

    private func role(_ relativePath: String) -> PreviewFolderRole {
        PreviewCandidateDetector.folderRole(
            for: songFolder.appendingPathComponent(relativePath),
            songFolder: songFolder
        )
    }

    func testClassifiesStandardSubfolders() {
        XCTAssertEqual(role("Neon Hook mix.wav"), .root)
        XCTAssertEqual(role("Mixdown/Neon Hook v2.wav"), .mixdown)
        XCTAssertEqual(role("Exports/Neon Hook.mp3"), .mixdown)
        XCTAssertEqual(role("Stems/Kick.wav"), .stems)
        XCTAssertEqual(role("Audio/Samples/loop.wav"), .samples)
        XCTAssertEqual(role("Audio/take 1.wav"), .other)
    }

    func testSongFolderPrefixIsOnlyStrippedAtTheStart() {
        // The song-folder text appearing again deeper in the path is part of the
        // relative path, never a second prefix to remove.
        XCTAssertEqual(role("Mixdown/Neon Hook/bounce.wav"), .mixdown)
        XCTAssertEqual(role("Songs/Neon Hook/Stems/bass.wav"), .stems)
    }

    func testUnstandardizedSongFolderStillMatches() {
        let messy = URL(fileURLWithPath: "/Volumes/Music/Songs/./Neon Hook/", isDirectory: true)
        let file = songFolder.appendingPathComponent("Mixdown/Neon Hook.wav")
        XCTAssertEqual(PreviewCandidateDetector.folderRole(for: file, songFolder: messy), .mixdown)
    }
}
