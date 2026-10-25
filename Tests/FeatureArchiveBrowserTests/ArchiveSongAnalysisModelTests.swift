import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// The song analysis owner on its own: results land only for the selected song, and the
/// caches follow a catalog change through the changed and removed songs.
@MainActor
final class ArchiveSongAnalysisModelTests: XCTestCase {
    private func makeSong(_ name: String, preview: String = "mix", previewModifiedAt: TimeInterval = 1_000) -> Song {
        let folder = URL(fileURLWithPath: "/tmp/song-analysis/\(name)", isDirectory: true)
        let candidate = PreviewCandidate(
            filePath: folder.appendingPathComponent("Mixdown/\(preview).wav"), fileName: "\(preview).wav",
            folderRole: .mixdown, modifiedAt: Date(timeIntervalSince1970: previewModifiedAt), detectedRole: .mainMix)
        let version = ProjectVersion(
            filePath: folder.appendingPathComponent("\(name).cpr"), fileName: "\(name).cpr",
            modifiedAt: Date(timeIntervalSince1970: 1_000))
        return Song(folderPath: folder, originalFolderName: name, displayTitle: name,
                    projectVersions: [version], previewCandidates: [candidate],
                    mainPreviewCandidateID: candidate.id, latestCPR: version)
    }

    private func makeModel(
        selected: @escaping @MainActor () -> Song?,
        bpm: @escaping ArchiveMixdownAnalysisCoordinator.BPMEstimator = { _ in MixdownBPMEstimate(bpm: 120, confidence: "test") }
    ) -> ArchiveSongAnalysisModel {
        ArchiveSongAnalysisModel(
            mixdown: ArchiveMixdownAnalysisCoordinator(
                bpmEstimator: bpm,
                keyEstimator: { _ in MixdownKeyEstimate(key: "C major", confidence: "test") }
            ),
            plugins: ArchiveCPRPluginCoordinator(processRunner: TestToolContext.make().processRunner),
            selectedSong: selected
        )
    }

    func testAResultLandsForTheSelectedSongAndPublishes() async throws {
        let song = makeSong("Selected")
        let model = makeModel(selected: { song })
        var publishes = 0
        let subscription = model.objectWillChange.sink { publishes += 1 }
        defer { subscription.cancel() }

        model.refreshMixdown(for: song)
        for _ in 0..<200 where model.bpmEstimate(for: song) == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.bpmEstimate(for: song)?.bpm, 120)
        XCTAssertEqual(model.keyEstimate(for: song)?.key, "C major")
        XCTAssertGreaterThan(publishes, 0, "the view model forwards these publishes to the views")
    }

    func testAResultForASongNoLongerSelectedIsDropped() async throws {
        let song = makeSong("Left")
        let other = makeSong("Other")
        var selected: Song? = song
        var selectionReads = 0
        let gate = AsyncGate()
        let model = makeModel(selected: { selectionReads += 1; return selected }, bpm: { _ in
            await gate.wait()
            return MixdownBPMEstimate(bpm: 99, confidence: "late")
        })

        model.refreshMixdown(for: song)
        selected = other
        await gate.open()
        // The finished load asks for the selection before it stores anything.
        for _ in 0..<200 where selectionReads == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertGreaterThan(selectionReads, 0)
        XCTAssertTrue(model.mixdownBPMBySongID.isEmpty, "a late result for another song never lands")
    }

    func testFollowDropsAChangedPreviewAndPrunesRemovedSongsOnly() throws {
        let changed = makeSong("Changed")
        let kept = makeSong("Kept")
        let removed = makeSong("Removed")
        let model = makeModel(selected: { nil })
        for song in [changed, kept, removed] {
            let key = try XCTUnwrap(ArchiveSongAnalysisModel.mixdownCacheKey(for: song))
            model.storeMixdownEstimates(cacheKey: key, bpm: MixdownBPMEstimate(bpm: 100, confidence: "test"), key: nil)
            let path = try XCTUnwrap(song.effectiveLatestCPR).filePath.standardizedFileURL.path
            model.storePluginSummary(CPRPluginSummary(pluginNames: ["EQ"], source: "fixture"), forCPRPath: path)
        }
        let after = makeSong("Changed", previewModifiedAt: 2_000)

        model.follow(
            SongCatalogChange(
                scannedChanged: true, visibleChanged: true,
                changed: [.init(before: changed, after: after)], removed: [removed]
            ),
            remainingSongIDs: { [changed.id, kept.id] },
            pluginsSectionExpanded: false
        )

        XCTAssertNil(model.bpmEstimate(for: changed), "a changed main preview drops its BPM")
        XCTAssertNotNil(model.bpmEstimate(for: kept))
        XCTAssertNil(model.bpmEstimate(for: removed), "a removed song leaves the cache")
        XCTAssertNotNil(model.pluginSummary(for: changed), "the project did not change")
        XCTAssertNotNil(model.pluginSummary(for: kept))
        XCTAssertNil(model.pluginSummary(for: removed))
    }

    func testFollowWithAnEmptyCatalogDropsEveryPluginSummary() throws {
        let song = makeSong("Only")
        let model = makeModel(selected: { nil })
        model.storePluginSummary(CPRPluginSummary(pluginNames: ["EQ"], source: "fixture"), forCPRPath: "/elsewhere.cpr")

        model.follow(
            SongCatalogChange(scannedChanged: true, visibleChanged: true, changed: [], removed: [song]),
            remainingSongIDs: { [] },
            pluginsSectionExpanded: false
        )

        XCTAssertTrue(model.cprPluginSummaryByCPRPath.isEmpty)
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
