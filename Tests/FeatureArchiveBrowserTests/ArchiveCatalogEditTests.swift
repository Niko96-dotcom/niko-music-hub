import AppCore
import Combine
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// What `applyCatalogEdit(_:)` does around a catalog write, seen through the view model.
@MainActor
final class ArchiveCatalogEditTests: XCTestCase {
    private func song(_ name: String, title: String? = nil) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: "/tmp/catalog-edit/\(name)", isDirectory: true),
            originalFolderName: name,
            displayTitle: title ?? name
        )
    }

    /// A song with a main preview and a project, so it has per-song cache keys.
    private func analyzedSong(_ index: Int) -> Song {
        let folder = URL(fileURLWithPath: "/tmp/catalog-edit/Analyzed \(index)", isDirectory: true)
        let candidate = PreviewCandidate(
            filePath: folder.appendingPathComponent("Mixdown/mix.wav"), fileName: "mix.wav",
            folderRole: .mixdown, modifiedAt: Date(timeIntervalSince1970: 1_000), detectedRole: .mainMix)
        let version = ProjectVersion(
            filePath: folder.appendingPathComponent("Analyzed \(index).cpr"), fileName: "Analyzed \(index).cpr",
            modifiedAt: Date(timeIntervalSince1970: 1_000))
        return Song(folderPath: folder, originalFolderName: "Analyzed \(index)", displayTitle: "Analyzed \(index)",
                    projectVersions: [version], previewCandidates: [candidate], mainPreviewCandidateID: candidate.id,
                    latestCPR: version)
    }

    /// Seeds a mixdown result and a plugin summary for `song`; returns their keys.
    private func seedPerSongCaches(for song: Song, in model: ArchiveBrowserViewModel) throws -> (mixdown: String, plugins: String) {
        let mixdownKey = try XCTUnwrap(ArchiveMixdownAnalysisCoordinator.cacheKey(for: song))
        let pluginsKey = try XCTUnwrap(song.effectiveLatestCPR).filePath.standardizedFileURL.path
        model.songAnalysis.storeMixdownEstimates(cacheKey: mixdownKey, bpm: MixdownBPMEstimate(bpm: 120, confidence: "low"), key: nil)
        model.songAnalysis.storePluginSummary(CPRPluginSummary(pluginNames: ["EQ"], source: "fixture"), forCPRPath: pluginsKey)
        return (mixdownKey, pluginsKey)
    }

    private func makeModel(_ songs: [Song]) -> ArchiveBrowserViewModel {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make(), archiveRootWatcher: NoopArchiveRootWatcher())
        model.applyCatalogEdit(.load(songs))
        return model
    }

    /// With no archived project shown, the visible list is the baseline itself, so the
    /// catalog holds one copy of its songs, not two.
    func testLoadWithoutArchivedProjectsKeepsOneCopyOfTheSongs() {
        let model = makeModel([song("A"), song("B")])

        let sameStorage = model.songs.withUnsafeBufferPointer { visible in
            model.scannedSongs.withUnsafeBufferPointer { scanned in visible.baseAddress == scanned.baseAddress }
        }
        XCTAssertTrue(sameStorage)
    }

    /// Replacing a song with an equal value changes nothing, so nothing publishes (B6).
    func testReplacingWithAnEqualSongPublishesNothing() {
        let neon = song("A", title: "Neon Hook")
        let model = makeModel([neon, song("B", title: "Ocean Drive")])
        var publications = 0
        let cancellable = model.objectWillChange.sink { _ in publications += 1 }
        defer { withExtendedLifetime(cancellable) {} }

        let change = model.applyCatalogEdit(.replace([neon]))

        XCTAssertTrue(change.isEmpty)
        XCTAssertEqual(publications, 0)
    }

    /// An edited song that stays in the filtered list stays selected with its new value.
    func testEditedSelectedSongStaysSelectedWithItsNewValue() {
        let neon = song("A", title: "Neon Hook")
        let model = makeModel([neon, song("B", title: "Ocean Drive")])
        model.browse.setSearchQuery("neon", immediate: true)
        model.selectSong(neon)

        let renamed = song("A", title: "Neon Hook (Remix)")
        model.applyCatalogEdit(.replace([renamed]))

        XCTAssertEqual(model.page.selectedSong, renamed)
        XCTAssertEqual(model.browse.filteredSongs, [renamed])
    }

    /// Per-song caches follow every edit, not only rescans: a song that leaves the
    /// catalog takes its mixdown result and plugin summary with it (B5).
    func testAnEditThatRemovesASongDropsItsPerSongResults() throws {
        let gone = analyzedSong(1), kept = analyzedSong(2)
        let model = makeModel([gone, kept])
        let goneKeys = try seedPerSongCaches(for: gone, in: model)
        let keptKeys = try seedPerSongCaches(for: kept, in: model)

        let change = model.applyCatalogEdit(.load([kept]))

        XCTAssertEqual(change.removed, [gone])
        XCTAssertNil(model.songAnalysis.mixdownBPMBySongID[goneKeys.mixdown])
        XCTAssertNil(model.songAnalysis.cprPluginSummaryByCPRPath[goneKeys.plugins])
        XCTAssertNotNil(model.songAnalysis.mixdownBPMBySongID[keptKeys.mixdown])
        XCTAssertNotNil(model.songAnalysis.cprPluginSummaryByCPRPath[keptKeys.plugins])
    }

    /// A root change empties the catalog, and the per-song caches with it.
    func testRootResetLeavesNoPerSongResults() throws {
        let first = analyzedSong(1), second = analyzedSong(2)
        let model = makeModel([first, second])
        _ = try seedPerSongCaches(for: first, in: model)
        _ = try seedPerSongCaches(for: second, in: model)

        model.clearRootBoundArchiveState(statusMessage: nil)

        XCTAssertTrue(model.songs.isEmpty)
        XCTAssertTrue(model.scannedSongs.isEmpty)
        XCTAssertTrue(model.songAnalysis.mixdownBPMBySongID.isEmpty)
        XCTAssertTrue(model.songAnalysis.cprPluginSummaryByCPRPath.isEmpty)
    }

    /// An edit that moves the selected song out of the filtered list deselects it:
    /// the browse recompute reconciles the selection, as before the catalog writer.
    func testEditThatMovesTheSelectedSongOutOfTheFilterDeselectsIt() {
        let neon = song("A", title: "Neon Hook")
        let model = makeModel([neon, song("B", title: "Ocean Drive")])
        model.browse.setSearchQuery("neon", immediate: true)
        model.selectSong(neon)

        model.applyCatalogEdit(.replace([song("A", title: "Sunset")]))

        XCTAssertNil(model.page.selectedSong)
        XCTAssertEqual(model.browse.filteredSongs, [])
    }
}
