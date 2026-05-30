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

    private func makeSong(name: String, previewModified: Date, cprModified: Date) -> Song {
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
            latestCPR: cpr
        )
    }
}
