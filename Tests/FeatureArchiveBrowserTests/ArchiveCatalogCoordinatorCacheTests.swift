import AppCore
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

@MainActor
final class ArchiveCatalogCoordinatorCacheTests: XCTestCase {
    func testCachedAutoSongReclassifiesLegacyVocalSelectionBeforePublishing() async {
        let root = URL(fileURLWithPath: "/tmp/preview-cache-root", isDirectory: true)
        let folder = root.appendingPathComponent("ONE LIME CAMP 4", isDirectory: true)
        let demoName = "drinking kinda situation demo v1 (day one 4).wav"
        let vocalsName = "drinking kinda situation demo v1 (day one 4) (Cover) (Vocals).wav"
        let demo = legacyCandidate(name: demoName, folder: folder, duration: 39)
        let vocals = legacyCandidate(name: vocalsName, folder: folder, duration: 87)
        let legacy = Song(
            folderPath: folder,
            originalFolderName: "ONE LIME CAMP 4",
            displayTitle: "ONE LIME CAMP 4",
            previewCandidates: [vocals, demo],
            mainPreviewCandidateID: vocals.id
        )
        let store = CachedArchiveIndexStore(
            snapshot: ArchiveIndexSnapshot(roots: [root.path], songs: [legacy], scannedAt: Date())
        )
        let coordinator = ArchiveCatalogCoordinator(
            archiveIndexStore: store,
            songMetadataStore: nil,
            collaboratorStore: nil,
            diagnostics: TestToolContext.make().diagnostics
        )

        let result = await coordinator.loadCachedSongsDetached(roots: [root], collaborators: [])

        guard case .loaded(let songs, _) = result,
              let loaded = songs.first,
              let reclassifiedVocals = loaded.previewCandidates.first(where: { $0.id == vocals.id }) else {
            return XCTFail("Expected the normalized cache song")
        }
        XCTAssertEqual(loaded.mainPreviewCandidateID, demo.id)
        XCTAssertEqual(reclassifiedVocals.detectedRole, .acapella)
        XCTAssertTrue(reclassifiedVocals.confidenceReasons.contains("filename:negative-cover"))
    }

    private func legacyCandidate(name: String, folder: URL, duration: Double) -> PreviewCandidate {
        PreviewCandidate(
            filePath: folder.appendingPathComponent(name),
            fileName: name,
            folderRole: .root,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectedRole: .mainMix,
            fileExtension: "wav",
            detectedVersionNumber: 4,
            durationSeconds: duration,
            confidenceScore: 51,
            confidenceReasons: ["role:full-mix", "duration:plausible", "recency"]
        )
    }
}

private final class CachedArchiveIndexStore: ArchiveIndexStoring, @unchecked Sendable {
    private let snapshot: ArchiveIndexSnapshot

    init(snapshot: ArchiveIndexSnapshot) {
        self.snapshot = snapshot
    }

    func loadLatest() throws -> ArchiveIndexSnapshot? { snapshot }
    func save(_ snapshot: ArchiveIndexSnapshot) throws {}
    func clear() throws {}
}
