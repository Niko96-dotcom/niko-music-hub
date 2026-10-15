import Foundation
@testable import FeatureArchiveBrowser
import NikoMusicCore
import XCTest

/// Count copy reads "1 version", "1 song in Done", "Done column, 1 song",
/// "across 1 stay" — never "1 versions" or "1 songs".
final class ArchiveCountLabelTests: XCTestCase {
    func testCountUsesSingularOnlyForOne() {
        XCTAssertEqual(CountCopy.count(0, "version"), "0 versions")
        XCTAssertEqual(CountCopy.count(1, "version"), "1 version")
        XCTAssertEqual(CountCopy.count(2, "version"), "2 versions")
        XCTAssertEqual(CountCopy.count(1, "stay"), "1 stay")
        XCTAssertEqual(CountCopy.count(3, "stay"), "3 stays")
        XCTAssertEqual(CountCopy.noun(for: 1, "song"), "song")
        XCTAssertEqual(CountCopy.noun(for: 12, "song"), "songs")
    }

    func testCountTakesAnIrregularPlural() {
        XCTAssertEqual(CountCopy.count(1, "match", plural: "matches"), "1 match")
        XCTAssertEqual(CountCopy.count(2, "match", plural: "matches"), "2 matches")
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
