import NikoMusicCore
import XCTest

final class ArchiveMetadataMergerTests: XCTestCase {
    func testSongVirtualTitleMutation() {
        var song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/x", isDirectory: true),
            originalFolderName: "x",
            displayTitle: "Scanner"
        )
        song.virtualTitle = "Virtual"
        XCTAssertEqual(song.effectiveDisplayTitle, "Virtual")
    }

    func testVirtualTitleOverridesDisplayTitle() {
        let folder = URL(fileURLWithPath: "/tmp/song-a", isDirectory: true)
        let scanned = Song(
            folderPath: folder,
            originalFolderName: "Disk Name",
            displayTitle: "Scanner Title"
        )
        let metadata = SongUserMetadata(songID: scanned.id, virtualTitle: "My Alias Title")
        let merged = ArchiveMetadataMerger.merge(scanned: scanned, metadata: metadata)
        XCTAssertEqual(merged.effectiveDisplayTitle, "My Alias Title")
        XCTAssertEqual(merged.originalFolderName, "Disk Name")
    }

    func testManualPreviewSurvivesWhenCandidateExists() {
        let folder = URL(fileURLWithPath: "/tmp/song-b", isDirectory: true)
        let first = PreviewCandidate(
            filePath: folder.appendingPathComponent("a.wav"),
            fileName: "a.wav",
            folderRole: .mixdown,
            modifiedAt: Date(),
            detectedRole: .mainMix
        )
        let second = PreviewCandidate(
            filePath: folder.appendingPathComponent("b.wav"),
            fileName: "b.wav",
            folderRole: .mixdown,
            modifiedAt: Date(),
            detectedRole: .mainMix
        )
        let scanned = Song(
            folderPath: folder,
            originalFolderName: "Song",
            displayTitle: "Song",
            previewCandidates: [first, second],
            mainPreviewCandidateID: "a"
        )
        let metadata = SongUserMetadata(
            songID: scanned.id,
            previewSelectionMode: .manual,
            manualMainPreviewID: second.id
        )
        let merged = ArchiveMetadataMerger.merge(scanned: scanned, metadata: metadata)
        XCTAssertEqual(merged.mainPreviewCandidateID, second.id)
        XCTAssertEqual(merged.previewSelectionMode, .manual)
    }

    func testIgnoredPreviewRemovedFromCandidates() {
        let folder = URL(fileURLWithPath: "/tmp/song-c", isDirectory: true)
        let keep = PreviewCandidate(
            filePath: folder.appendingPathComponent("keep.wav"),
            fileName: "keep.wav",
            folderRole: .mixdown,
            modifiedAt: Date(),
            detectedRole: .mainMix
        )
        let drop = PreviewCandidate(
            filePath: folder.appendingPathComponent("drop.wav"),
            fileName: "drop.wav",
            folderRole: .mixdown,
            modifiedAt: Date(),
            detectedRole: .mainMix
        )
        let scanned = Song(
            folderPath: folder,
            originalFolderName: "Song",
            displayTitle: "Song",
            previewCandidates: [keep, drop],
            mainPreviewCandidateID: "keep"
        )
        let metadata = SongUserMetadata(
            songID: scanned.id,
            ignoredPreviewCandidateIDs: [drop.id]
        )
        let merged = ArchiveMetadataMerger.merge(scanned: scanned, metadata: metadata)
        XCTAssertEqual(merged.previewCandidates.map(\.id), [keep.id])
    }
}
