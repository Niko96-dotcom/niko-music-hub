import NikoMusicCore
import XCTest

final class ArchiveShelfRankerTests: XCTestCase {
    func testRecentlyBouncedOrdersByNewestMixdown() throws {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)
        let older = makeSong(name: "Older", previewModified: oldDate, cprModified: oldDate)
        let newer = makeSong(name: "Newer", previewModified: newDate, cprModified: oldDate)
        let ranked = ArchiveShelfRanker.recentlyBounced([older, newer])
        XCTAssertEqual(ranked.map(\.originalFolderName), ["Newer", "Older"])
    }

    func testRecentCPROrdersByNewestProjectFile() throws {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)
        let older = makeSong(name: "Older", previewModified: newDate, cprModified: oldDate)
        let newer = makeSong(name: "Newer", previewModified: oldDate, cprModified: newDate)
        let ranked = ArchiveShelfRanker.recentCPRActivity([older, newer])
        XCTAssertEqual(ranked.map(\.originalFolderName), ["Newer", "Older"])
    }

    func testQuietSongsSurfacesStaleUnfinishedWorkOldestFirst() throws {
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let fortyDaysAgo = now.addingTimeInterval(-40 * 86_400)
        let sixtyDaysAgo = now.addingTimeInterval(-60 * 86_400)
        let fresh = now.addingTimeInterval(-5 * 86_400)

        let stale = makeSong(name: "Stale", previewModified: fortyDaysAgo, cprModified: fortyDaysAgo, workflowStatus: .prod)
        let staler = makeSong(name: "Staler", previewModified: sixtyDaysAgo, cprModified: sixtyDaysAgo, workflowStatus: .song)
        let active = makeSong(name: "Active", previewModified: fresh, cprModified: fresh, workflowStatus: .prod)
        let finished = makeSong(name: "Finished", previewModified: sixtyDaysAgo, cprModified: sixtyDaysAgo, workflowStatus: .done)
        let untriaged = makeSong(name: "Untriaged", previewModified: sixtyDaysAgo, cprModified: sixtyDaysAgo, workflowStatus: nil)

        let quiet = ArchiveShelfRanker.quietSongs([stale, staler, active, finished, untriaged], now: now)
        XCTAssertEqual(quiet.map(\.originalFolderName), ["Staler", "Stale"])

        let viaFilter = ArchiveShelfRanker.filter([stale, active], shelf: .quietSongs, now: now)
        XCTAssertEqual(viaFilter.map(\.originalFolderName), ["Stale"])
    }

    func testWorkflowStageProgressSpansPipeline() {
        XCTAssertEqual(ProjectWorkflowStatus.songstarterBeat.stagePosition, 1)
        XCTAssertEqual(ProjectWorkflowStatus.done.stagePosition, ProjectWorkflowStatus.stageCount)
        XCTAssertEqual(ProjectWorkflowStatus.done.pipelineProgress, 1.0)
        for status in ProjectWorkflowStatus.allCases {
            XCTAssertGreaterThan(status.pipelineProgress, 0)
            XCTAssertLessThanOrEqual(status.pipelineProgress, 1.0)
        }
    }

    private func makeSong(
        name: String,
        previewModified: Date,
        cprModified: Date,
        workflowStatus: ProjectWorkflowStatus? = nil
    ) -> Song {
        let folder = URL(fileURLWithPath: "/tmp/\(name)", isDirectory: true)
        let preview = PreviewCandidate(
            filePath: folder.appendingPathComponent("mix.wav"),
            fileName: "mix.wav",
            folderRole: .mixdown,
            modifiedAt: previewModified,
            detectedRole: .mainMix
        )
        let cpr = ProjectVersion(
            filePath: folder.appendingPathComponent("\(name).cpr"),
            fileName: "\(name).cpr",
            modifiedAt: cprModified
        )
        return Song(
            folderPath: folder,
            originalFolderName: name,
            displayTitle: name,
            projectVersions: [cpr],
            previewCandidates: [preview],
            mainPreviewCandidateID: preview.id,
            latestCPR: cpr,
            workflowStatus: workflowStatus
        )
    }
}
