import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

final class ArchiveBoardProjectionTests: XCTestCase {
    private func song(_ path: String, title: String, status: ProjectWorkflowStatus?, cprModified: Date? = nil) -> Song {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let versions: [ProjectVersion] = cprModified.map {
            [ProjectVersion(
                filePath: folder.appendingPathComponent("\(title).cpr"),
                fileName: "\(title).cpr",
                modifiedAt: $0
            )]
        } ?? []
        return Song(
            folderPath: folder,
            originalFolderName: title,
            displayTitle: title,
            projectVersions: versions,
            workflowStatus: status
        )
    }

    func testColumnsCoverNoStatusAndEveryStageInPipelineOrder() {
        let columns = ArchiveBoardProjection.columns(from: [])
        XCTAssertEqual(columns.count, ProjectWorkflowStatus.allCases.count + 1)
        XCTAssertNil(columns[0].status)
        XCTAssertEqual(columns.dropFirst().map(\.status), ProjectWorkflowStatus.allCases)
        XCTAssertTrue(columns.allSatisfy(\.songs.isEmpty))
    }

    func testSongsLandInTheirStatusColumn() {
        let idea = song("/tmp/idea", title: "Idea", status: .songstarterBeat)
        let untriaged = song("/tmp/untriaged", title: "Untriaged", status: nil)
        let finished = song("/tmp/finished", title: "Finished", status: .done)

        let columns = ArchiveBoardProjection.columns(from: [idea, untriaged, finished])
        let byID = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0) })

        XCTAssertEqual(byID["no_status"]?.songs.map(\.id), [untriaged.id])
        XCTAssertEqual(byID[ProjectWorkflowStatus.songstarterBeat.rawValue]?.songs.map(\.id), [idea.id])
        XCTAssertEqual(byID[ProjectWorkflowStatus.done.rawValue]?.songs.map(\.id), [finished.id])
    }

    /// A placed song keeps its place among the others, whose order still
    /// comes from recent work; placing writes only the moved song.
    func testPlacedSongsKeepTheirPlaceAmongSongsOrderedByRecentWork() {
        let newest = song("/tmp/newest", title: "Newest", status: .song, cprModified: Date(timeIntervalSince1970: 3_000))
        let middle = song("/tmp/middle", title: "Middle", status: .song, cprModified: Date(timeIntervalSince1970: 2_000))
        let oldest = song("/tmp/oldest", title: "Oldest", status: .song, cprModified: Date(timeIntervalSince1970: 1_000))
        let lane = ArchiveBoardProjection.columns(from: [oldest, middle, newest])[2].songs
        XCTAssertEqual(lane.map(\.displayTitle), ["Newest", "Middle", "Oldest"])

        // The oldest song placed at the top, then the newest placed last.
        var placed = oldest
        placed.boardPosition = ArchiveBoardProjection.position(insertingAt: 0, in: [newest, middle])
        var columns = ArchiveBoardProjection.columns(from: [placed, middle, newest])
        XCTAssertEqual(columns[2].songs.map(\.displayTitle), ["Oldest", "Newest", "Middle"])

        var last = newest
        last.boardPosition = ArchiveBoardProjection.position(insertingAt: 2, in: [placed, middle])
        columns = ArchiveBoardProjection.columns(from: [placed, middle, last])
        XCTAssertEqual(columns[2].songs.map(\.displayTitle), ["Oldest", "Middle", "Newest"])

        // Between two neighbours.
        var between = middle
        between.boardPosition = ArchiveBoardProjection.position(insertingAt: 1, in: [placed, last])
        columns = ArchiveBoardProjection.columns(from: [placed, between, last])
        XCTAssertEqual(columns[2].songs.map(\.displayTitle), ["Oldest", "Middle", "Newest"])
        XCTAssertGreaterThan(between.boardPosition!, placed.boardPosition!)
        XCTAssertLessThan(between.boardPosition!, last.boardPosition!)

        // A search keeps its relevance order, placed or not.
        let searched = ArchiveBoardProjection.columns(from: [last, placed], preservingOrder: true)
        XCTAssertEqual(searched[2].songs.map(\.displayTitle), ["Newest", "Oldest"])
    }

    func testColumnsSortByNewestCPRThenTitle() {
        let older = song("/tmp/older", title: "Older", status: .prod, cprModified: Date(timeIntervalSince1970: 1_000))
        let newer = song("/tmp/newer", title: "Newer", status: .prod, cprModified: Date(timeIntervalSince1970: 2_000))
        let alphaNoCPR = song("/tmp/alpha", title: "Alpha", status: .prod)
        let betaNoCPR = song("/tmp/beta", title: "Beta", status: .prod)

        let columns = ArchiveBoardProjection.columns(from: [betaNoCPR, older, alphaNoCPR, newer])
        let prodColumn = columns.first { $0.status == .prod }

        XCTAssertEqual(
            prodColumn?.songs.map(\.originalFolderName),
            ["Newer", "Older", "Alpha", "Beta"]
        )
    }
    func testDateProjectionPreservesManualIgnoredAndEqualDateOrdering() {
        let date = Date(timeIntervalSince1970: 10_000)
        let songs = (0..<40).map { i -> Song in
            var value = song("/fixture/\(i)", title: "Title \(i % 4)",
                             status: i % 3 == 0 ? nil : .prod, cprModified: date)
            let newer = ProjectVersion(filePath: value.folderPath.appendingPathComponent("new.cpr"),
                                       fileName: "new.cpr", modifiedAt: date.addingTimeInterval(10_000))
            value.projectVersions.append(newer)
            value.latestCPR = newer
            if i % 2 == 0 { value.ignoredCPRVersionIDs = [newer.id] }
            if i % 5 == 0 {
                value.cprSelectionMode = .manual
                value.manualMainCPRID = value.projectVersions[0].id
            }
            return value
        }
        let columns = ArchiveBoardProjection.columns(from: songs)
        for column in columns {
            let expected = songs.filter { $0.workflowStatus == column.status }.sorted { lhs, rhs in
                let left = ArchiveShelfRanker.latestCPRActivity(for: lhs) ?? .distantPast
                let right = ArchiveShelfRanker.latestCPRActivity(for: rhs) ?? .distantPast
                if left != right { return left > right }
                return lhs.effectiveDisplayTitle.localizedCaseInsensitiveCompare(rhs.effectiveDisplayTitle) == .orderedAscending
            }
            XCTAssertEqual(column.songs, expected)
        }
    }

}
