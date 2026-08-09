import XCTest
@testable import NikoMusicCore

final class PreviewAutoSelectionNormalizerTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testLegacyAutoSnapshotReclassifiesCoverVocalsAndSelectsFullDemo() {
        let (song, demo, vocals) = legacySong()

        let normalized = PreviewAutoSelectionNormalizer.normalized(song)
        let normalizedVocals = normalized.previewCandidates.first { $0.id == vocals.id }

        XCTAssertEqual(normalized.mainPreviewCandidateID, demo.id)
        XCTAssertEqual(normalized.previewCandidates.first?.id, demo.id)
        XCTAssertEqual(normalizedVocals?.detectedRole, .acapella)
        XCTAssertTrue(normalizedVocals?.confidenceReasons.contains("filename:negative-cover") == true)
        XCTAssertTrue(normalizedVocals?.confidenceReasons.contains("filename:negative-vocals") == true)
    }

    func testManualSnapshotIsNotReclassifiedOrReselected() {
        var song = legacySong().song
        song.previewSelectionMode = .manual

        XCTAssertEqual(PreviewAutoSelectionNormalizer.normalized(song), song)
    }

    func testIgnoredCachedCandidateStaysHiddenFromAutomaticSelection() {
        var song = legacySong().song
        let demo = song.previewCandidates.first { $0.fileName.hasSuffix("day one 4).wav") }!
        let vocals = song.previewCandidates.first { $0.fileName.contains("(Vocals)") }!
        song.ignoredPreviewCandidateIDs = [demo.id]

        let normalized = PreviewAutoSelectionNormalizer.normalized(song)

        XCTAssertEqual(normalized.previewCandidates.map(\.id), [vocals.id])
        XCTAssertEqual(normalized.mainPreviewCandidateID, vocals.id)
    }

    private func legacySong() -> (song: Song, demo: PreviewCandidate, vocals: PreviewCandidate) {
        let folder = URL(fileURLWithPath: "/tmp/legacy-preview", isDirectory: true)
        let demoName = "drinking kinda situation demo v1 (day one 4).wav"
        let vocalsName = "drinking kinda situation demo v1 (day one 4) (Cover) (Vocals).wav"
        let demo = legacyCandidate(name: demoName, folder: folder, duration: 39)
        let vocals = legacyCandidate(name: vocalsName, folder: folder, duration: 87)
        let song = Song(
            folderPath: folder,
            originalFolderName: "ONE LIME CAMP 4",
            displayTitle: "ONE LIME CAMP 4",
            previewCandidates: [vocals, demo],
            mainPreviewCandidateID: vocals.id
        )
        return (song, demo, vocals)
    }

    private func legacyCandidate(name: String, folder: URL, duration: Double) -> PreviewCandidate {
        PreviewCandidate(
            filePath: folder.appendingPathComponent(name),
            fileName: name,
            folderRole: .root,
            modifiedAt: date,
            detectedRole: .mainMix,
            fileExtension: "wav",
            detectedVersionNumber: 4,
            durationSeconds: duration,
            confidenceScore: 51,
            confidenceReasons: ["role:full-mix", "duration:plausible", "recency"]
        )
    }
}
