import AppCore
import Combine
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// A rescan hands back the whole catalog. Applying it reacts to the songs that changed and leaves an unchanged catalog
/// alone: no second copy kept, no browse list projected again, nothing invalidated.
@MainActor
final class ArchiveRescanApplyTests: XCTestCase {
    private func makeSong(_ index: Int, mainPreview: String = "mix") -> Song {
        let folder = URL(fileURLWithPath: "/tmp/rescan-apply/Song \(index)", isDirectory: true)
        let candidate = PreviewCandidate(
            filePath: folder.appendingPathComponent("Mixdown/\(mainPreview).wav"), fileName: "\(mainPreview).wav",
            folderRole: .mixdown, modifiedAt: Date(timeIntervalSince1970: 1_000), detectedRole: .mainMix)
        let version = ProjectVersion(
            filePath: folder.appendingPathComponent("Song \(index).cpr"), fileName: "Song \(index).cpr",
            modifiedAt: Date(timeIntervalSince1970: 1_000 + Double(index)))
        return Song(folderPath: folder, originalFolderName: "Song \(index)", displayTitle: "Song \(index)",
                    projectVersions: [version], previewCandidates: [candidate], mainPreviewCandidateID: candidate.id, latestCPR: version)
    }

    private func makeModel(_ songs: [Song]) -> ArchiveBrowserViewModel {
        let model = ArchiveBrowserViewModel(context: TestToolContext.make(), archiveRootWatcher: NoopArchiveRootWatcher())
        model.applyCatalogEdit(.load(songs))
        model.recomputeBrowseResults()
        return model
    }

    private func update(_ model: ArchiveBrowserViewModel, songs: [Song]) -> ArchiveCatalogCoordinator.CatalogScanApplyResult {
        model.catalog.applyFullScanResult(result: ScanResult(songs: songs), roots: [], collaborators: [], scannedAt: Date())
    }

    private func sameStorage(_ left: [Song], _ right: [Song]) -> Bool {
        left.withUnsafeBufferPointer { l in right.withUnsafeBufferPointer { r in l.baseAddress == r.baseAddress } }
    }

    func testUnchangedRescanKeepsTheHeldCatalogAndDoesNotProjectTheBrowseListAgain() {
        let model = makeModel((0..<600).map { makeSong($0) })
        let heldSongs = model.songs
        let heldScanned = model.scannedSongs
        let heldFiltered = model.filteredSongs
        var filteredPublishes = 0
        let subscription = model.$filteredSongs.dropFirst().sink { _ in filteredPublishes += 1 }
        defer { subscription.cancel() }

        // The same catalog, built again: equal values that share no storage with the held ones.
        let rescanned = update(model, songs: (0..<600).map { makeSong($0) })
        model.applyCatalogScanUpdate(rescanned, roots: [])

        XCTAssertTrue(sameStorage(model.songs, heldSongs), "the held catalog is kept, not replaced by an equal copy")
        XCTAssertTrue(sameStorage(model.scannedSongs, heldScanned))
        XCTAssertTrue(sameStorage(model.filteredSongs, heldFiltered), "the browse list was not projected again")
        XCTAssertEqual(filteredPublishes, 0)
        XCTAssertEqual(model.scanDiagnostics, rescanned.diagnostics, "the scan summary still updates")
        XCTAssertEqual(model.statusMessage, rescanned.statusMessage)
    }

    func testChangedSongReplacesTheCatalogReprojectsAndInvalidatesOnlyItsPreviewAnalysis() throws {
        let songs = (0..<50).map { makeSong($0) }
        let model = makeModel(songs)
        let changedKey = try XCTUnwrap(ArchiveMixdownAnalysisCoordinator.cacheKey(for: songs[7]))
        let untouchedKey = try XCTUnwrap(ArchiveMixdownAnalysisCoordinator.cacheKey(for: songs[8]))
        model.songAnalysis.storeMixdownEstimates(cacheKey: changedKey, bpm: MixdownBPMEstimate(bpm: 120, confidence: "high"), key: nil)
        model.songAnalysis.storeMixdownEstimates(cacheKey: untouchedKey, bpm: MixdownBPMEstimate(bpm: 90, confidence: "high"), key: nil)

        var next = songs
        next[7] = makeSong(7, mainPreview: "master")
        model.applyCatalogScanUpdate(update(model, songs: next), roots: [])

        XCTAssertEqual(model.songs[7].mainPreviewCandidateID, next[7].mainPreviewCandidateID)
        XCTAssertEqual(model.filteredSongs.count, 50)
        XCTAssertNil(model.songAnalysis.mixdownBPMBySongID[changedKey], "the song's main preview changed")
        XCTAssertNotNil(model.songAnalysis.mixdownBPMBySongID[untouchedKey], "an unchanged song keeps its analysis")
    }

    func testChangedProjectInvalidatesItsPluginSummaryOnly() {
        let songs = (0..<20).map { makeSong($0) }
        let model = makeModel(songs)
        let oldPath = songs[3].effectiveLatestCPR!.filePath.standardizedFileURL.path
        let otherPath = songs[4].effectiveLatestCPR!.filePath.standardizedFileURL.path
        model.songAnalysis.storePluginSummary(CPRPluginSummary(pluginNames: ["EQ"], source: "fixture"), forCPRPath: oldPath)
        model.songAnalysis.storePluginSummary(CPRPluginSummary(pluginNames: ["Comp"], source: "fixture"), forCPRPath: otherPath)

        var next = songs
        let newer = ProjectVersion(
            filePath: songs[3].effectiveLatestCPR!.filePath, fileName: songs[3].effectiveLatestCPR!.fileName,
            modifiedAt: Date(timeIntervalSince1970: 9_999))
        next[3].projectVersions = [newer]
        next[3].latestCPR = newer
        model.applyCatalogScanUpdate(update(model, songs: next), roots: [])

        XCTAssertNil(model.songAnalysis.cprPluginSummaryByCPRPath[oldPath])
        XCTAssertNotNil(model.songAnalysis.cprPluginSummaryByCPRPath[otherPath])
    }

    func testRemovedSongIsPrunedFromTheAnalysisCaches() throws {
        let songs = (0..<10).map { makeSong($0) }
        let model = makeModel(songs)
        let goneKey = try XCTUnwrap(ArchiveMixdownAnalysisCoordinator.cacheKey(for: songs[2]))
        let keptKey = try XCTUnwrap(ArchiveMixdownAnalysisCoordinator.cacheKey(for: songs[3]))
        model.songAnalysis.storeMixdownEstimates(cacheKey: goneKey, bpm: MixdownBPMEstimate(bpm: 100, confidence: "low"), key: nil)
        model.songAnalysis.storeMixdownEstimates(cacheKey: keptKey, bpm: MixdownBPMEstimate(bpm: 110, confidence: "low"), key: nil)

        var next = songs
        next.remove(at: 2)
        model.applyCatalogScanUpdate(update(model, songs: next), roots: [])

        XCTAssertEqual(model.songs.count, 9)
        XCTAssertNil(model.songAnalysis.mixdownBPMBySongID[goneKey])
        XCTAssertNotNil(model.songAnalysis.mixdownBPMBySongID[keptKey])
    }

    func testIntelligencePassStillRunsAfterAnUnchangedRescan() {
        let model = makeModel((0..<30).map { makeSong($0) })
        // `scan()` ends dismissals before a rescan lands; the intelligence pass then runs again on apply.
        let before = model.intelligence.refreshTask
        model.applyCatalogScanUpdate(update(model, songs: (0..<30).map { makeSong($0) }), roots: [])
        XCTAssertNotNil(model.intelligence.refreshTask)
        XCTAssertNotEqual(model.intelligence.refreshTask, before, "the intelligence refresh was scheduled")
    }
}
