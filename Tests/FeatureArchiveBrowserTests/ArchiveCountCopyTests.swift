import Foundation
@testable import FeatureArchiveBrowser
import XCTest

/// Count copy in the song detail rail and Analytics read "1 version",
/// "1 song in Done", "across 1 stay" — never "1 versions".
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

    func testDetailRailAndAnalyticsHaveNoHardcodedPluralCounts() throws {
        // A raw interpolated count followed by a fixed plural noun is the bug:
        // "\(count) versions" reads "1 versions".
        let pattern = #"\\\([^()]*(\([^()]*\))?[^()]*\) (versions|songs|saves|stays|months)\b"#
        let regex = try NSRegularExpression(pattern: pattern)
        for path in [
            "Sources/FeatureArchiveBrowser/SongDetailView.swift",
            "Sources/FeatureArchiveBrowser/ArchiveAnalyticsView.swift",
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
}
