import XCTest

/// Opening a song detail allocates no playback and stats no cloud file on the main thread, and its
/// preview candidates are paged. AGENTS.md row "Preview is output-only"; docs/architecture.md
/// § Archive preview playback.
final class ArchiveDetailPerformanceSourceTests: XCTestCase {
    static let rule = RepoRule(
        name: "Song detail mounts cheaply",
        why: "A player per detail, or a stat of every cloud version, made opening a song slow on large archives",
        see: "AGENTS.md row \"Preview is output-only\"; docs/architecture.md § Archive preview playback",
        fix: "Play through the one ArchivePreviewSession and page candidates with ArchivePreviewCandidatePagination"
    )

    private static let detail = "Sources/FeatureArchiveBrowser/SongDetailView.swift"

    func testDetailMountDoesNotAllocatePlaybackResources() {
        Self.rule.expect(Self.detail, lacks: ["ArchivePreviewPlayer()", ".prepare(url:"])
        Self.rule.expect(Self.detail, lacks: ["resourceValues(forKeys:"], because: "rendering versions must not stat cloud files on main")
    }

    func testDetailUsesBoundedCandidatePaging() {
        Self.rule.expect(
            Self.detail,
            contains: [
                "Text(\"Main project\")", "ArchivePreviewCandidatePagination.page", "LazyVStack",
                "Page \\(page.index + 1) of \\(page.pageCount)",
            ],
            lacks: ["ForEach(alternates, id:"]
        )
    }
}
