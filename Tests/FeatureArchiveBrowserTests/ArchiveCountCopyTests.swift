import Foundation
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

/// Count copy reads "1 version", "1 song in Done", "Done column, 1 song",
/// "across 1 stay" — never "1 versions" or "1 songs".
final class ArchiveCountCopyTests: XCTestCase {
    func testCountUsesSingularOnlyForOne() {
        XCTAssertEqual(ArchiveCountCopy.count(0, "version"), "0 versions")
        XCTAssertEqual(ArchiveCountCopy.count(1, "version"), "1 version")
        XCTAssertEqual(ArchiveCountCopy.count(2, "version"), "2 versions")
        XCTAssertEqual(ArchiveCountCopy.count(1, "stay"), "1 stay")
        XCTAssertEqual(ArchiveCountCopy.count(3, "stay"), "3 stays")
        XCTAssertEqual(ArchiveCountCopy.noun(for: 1, "song"), "song")
        XCTAssertEqual(ArchiveCountCopy.noun(for: 12, "song"), "songs")
    }

    func testCountTakesAnIrregularPlural() {
        XCTAssertEqual(ArchiveCountCopy.count(1, "match", plural: "matches"), "1 match")
        XCTAssertEqual(ArchiveCountCopy.count(2, "match", plural: "matches"), "2 matches")
    }

    func testBoardColumnLabelSaysOneSong() {
        let solo = song(named: "Solo", status: .song)
        let duo = song(named: "Duo", status: .done)

        XCTAssertEqual(ArchiveBoardColumn(status: .song, songs: [solo]).accessibilityLabel, "Song column, 1 song")
        XCTAssertEqual(ArchiveBoardColumn(status: .done, songs: []).accessibilityLabel, "Done column, 0 songs")
        XCTAssertEqual(ArchiveBoardColumn(status: nil, songs: [solo, duo]).accessibilityLabel, "No Status column, 2 songs")
    }

    func testSidebarHealthAndFilesystemStatusSayOneSong() {
        let solo = song(named: "Solo", warnings: ["No preview"])
        let health = ArchiveSidebarHealthContext.make(report: ArchiveHealthReport(songs: [solo]), skippedEntryCount: 0)
        XCTAssertEqual(health.summary, "1 song · 1 warning")

        let diagnostics = ArchiveScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1),
            rootPaths: ["/tmp/nmh-count"],
            songCount: 1,
            songsWithWarningsCount: 0,
            totalSongWarningCount: 0,
            globalWarnings: [],
            songWarningSummaries: [],
            skippedEntries: []
        )
        func update(updated: Int, title: String?) -> String {
            ArchiveCatalogCoordinator.IncrementalFilesystemApplyResult(
                songs: [solo],
                diagnostics: diagnostics,
                incrementalSongCount: updated,
                firstUpdatedTitle: title,
                scannedAt: Date(timeIntervalSince1970: 1),
                persistenceWarning: nil,
                metadataLoad: nil
            ).statusMessage
        }
        XCTAssertEqual(update(updated: 1, title: "Solo"), "Updated Solo from filesystem change (1 song).")
        XCTAssertEqual(update(updated: 1, title: nil), "Updated 1 song from filesystem change (1 total).")
    }

    func testArchiveCountCopyHasNoHardcodedPluralCounts() throws {
        // A raw interpolated count followed by a fixed plural noun is the bug:
        // "\(count) versions" reads "1 versions".
        let pattern = #"\\\([^()]*(\([^()]*\))?[^()]*\) (versions|songs|saves|stays|months|warnings)\b"#
        let regex = try NSRegularExpression(pattern: pattern)
        for path in [
            "Sources/FeatureArchiveBrowser/SongDetailView.swift",
            "Sources/FeatureArchiveBrowser/ArchiveAnalyticsView.swift",
            "Sources/FeatureArchiveBrowser/ArchiveBoardColumnView.swift",
            "Sources/FeatureArchiveBrowser/ArchiveBoardProjection.swift",
            "Sources/FeatureArchiveBrowser/ArchiveSidebarHealthContext.swift",
            "Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel+Scan.swift",
            "Sources/FeatureArchiveBrowser/ArchiveBrowserViewModel+Exports.swift",
        ] {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            let hits = regex.matches(in: source, range: range).compactMap {
                Range($0.range, in: source).map { String(source[$0]) }
            }
            XCTAssertEqual(hits, [], "\(path) hardcodes a plural after a count")
        }
        let detail = try String(contentsOfFile: "Sources/FeatureArchiveBrowser/SongDetailView.swift", encoding: .utf8)
        XCTAssertTrue(detail.contains("ArchiveCountCopy.count(liveSong.visibleProjectVersions.count, \"version\")"))
        let analytics = try String(contentsOfFile: "Sources/FeatureArchiveBrowser/ArchiveAnalyticsView.swift", encoding: .utf8)
        XCTAssertTrue(analytics.contains("ArchiveCountCopy.count(stage.count, \"song\")) in"))
        XCTAssertTrue(analytics.contains("ArchiveCountCopy.count(dwell.sampleCount, \"stay\")"))
        XCTAssertTrue(analytics.contains("ArchiveCountCopy.noun(for: overview.totalSongs, \"song\")"))
    }

    private func song(named name: String, status: ProjectWorkflowStatus? = nil, warnings: [String] = []) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: "/tmp/nmh-count/\(name)", isDirectory: true),
            originalFolderName: name,
            displayTitle: name,
            scanWarnings: warnings,
            workflowStatus: status
        )
    }
}
