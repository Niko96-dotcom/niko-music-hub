import XCTest

final class ArchiveDetailPerformanceSourceTests: XCTestCase {
    func testDetailHeroDefersHeavyPlaybackPreparation() throws {
        let hero = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveWaveformHeroView.swift",
            encoding: .utf8
        )
        let player = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveMiniPlayerView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(hero.contains("await Task.yield()"))
        XCTAssertTrue(hero.contains("playback.prefetch(url: url)"))
        XCTAssertFalse(hero.contains("playback.prepare(url: url)"))
        XCTAssertTrue(player.contains("func prefetch(url"))
        XCTAssertTrue(player.contains("includesHook: false"))
    }

    func testDetailUsesBoundedCandidatePaging() throws {
        let detail = try String(
            contentsOfFile: "Sources/FeatureArchiveBrowser/SongDetailView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(detail.contains("CURRENT PREVIEW"))
        XCTAssertTrue(detail.contains("ArchivePreviewCandidatePagination.page"))
        XCTAssertTrue(detail.contains("LazyVStack"))
        XCTAssertTrue(detail.contains("Page \\(page.index + 1) of \\(page.pageCount)"))
        XCTAssertFalse(detail.contains("ForEach(alternates, id:"))
    }
}
