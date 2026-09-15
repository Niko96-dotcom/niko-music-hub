import XCTest
import NikoMusicCore
@testable import FeatureArchiveBrowser

final class ArchivePreviewCandidateFilterTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/fixture/song")

    private func candidate(_ path: String) -> PreviewCandidate {
        let url = root.appendingPathComponent(path)
        return PreviewCandidate(filePath: url, fileName: url.lastPathComponent,
            folderRole: .mixdown, modifiedAt: Date(), detectedRole: .mainMix)
    }

    func testFilenameFilterPreservesOrderAndIdentity() {
        let candidates = [candidate("A/Démo V2.wav"), candidate("B/Demo V1.wav"), candidate("Demo/Other.wav")]
        XCTAssertEqual(ArchivePreviewCandidateFilter.candidates(candidates, matching: "DEMO wav").map(\.id), Array(candidates.prefix(2)).map(\.id))
        XCTAssertEqual(ArchivePreviewCandidateFilter.candidates(candidates, matching: "  ").map(\.id), candidates.map(\.id))
        XCTAssertTrue(ArchivePreviewCandidateFilter.candidates(candidates, matching: "missing").isEmpty)
    }

    func testDuplicateLabelsDistinguishFoldersAndLeaveUniqueNamesQuiet() {
        let candidates = [candidate("A/Mix.wav"), candidate("B/Mix.wav"), candidate("Mix.wav"), candidate("Unique.wav")]
        let labels = ArchivePreviewCandidateFilter.folderLabels(for: candidates, relativeTo: root)
        XCTAssertEqual(labels[candidates[0].id], "A")
        XCTAssertEqual(labels[candidates[1].id], "B")
        XCTAssertEqual(labels[candidates[2].id], "Project folder")
        XCTAssertNil(labels[candidates[3].id])
        XCTAssertEqual(Set(candidates.map(\.id)).count, 4)
    }

    func testFilteredPageClampsAfterCandidateRemovalAndHandlesNoMatches() {
        let candidates = (0..<50).map { candidate("Mix \($0).wav") }
        let filtered = ArchivePreviewCandidateFilter.candidates(candidates, matching: "Mix 1")
        let page = ArchivePreviewCandidatePagination.page(from: filtered, requestedIndex: 2)
        XCTAssertEqual(page.index, 0)
        XCTAssertEqual(page.elements.map(\.id), filtered.map(\.id))
        let empty = ArchivePreviewCandidatePagination.page(from: ArchivePreviewCandidateFilter.candidates(candidates, matching: "none"), requestedIndex: 2)
        XCTAssertEqual(empty.index, 0)
        XCTAssertTrue(empty.elements.isEmpty)
    }
}
