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
}
