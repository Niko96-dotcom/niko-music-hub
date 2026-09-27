import NikoMusicCore
@testable import FeatureArchiveBrowser
import XCTest

final class ArchiveBrowseProjectionTests: XCTestCase {
    func testProjectEmptySearchAppliesFilterAndSort() {
        let songA = Song(
            folderPath: URL(fileURLWithPath: "/tmp/alpha"),
            originalFolderName: "Alpha",
            displayTitle: "Alpha"
        )
        let songB = Song(
            folderPath: URL(fileURLWithPath: "/tmp/beta"),
            originalFolderName: "Beta",
            displayTitle: "Beta",
            scanWarnings: ["missing preview"]
        )
        var state = ArchiveBrowseState(
            songs: [songA, songB],
            showHiddenSongs: true,
            selectedShelf: .allSongs,
            selectedCollaboratorID: nil,
            searchQuery: "",
            browseFilter: [.hasWarnings],
            sortMode: .titleAZ,
            skippedScanEntries: []
        )

        let result = ArchiveBrowseProjection.project(state)
        XCTAssertEqual(result.filteredSongs.map(\.id), [songB.id])
        XCTAssertTrue(result.searchMatchSummaries.isEmpty)

        state.browseFilter = []
        state.searchQuery = "alp"
        let searched = ArchiveBrowseProjection.project(state)
        XCTAssertEqual(searched.filteredSongs.map(\.id), [songA.id])
        XCTAssertFalse(searched.searchMatchSummaries[songA.id, default: ""].isEmpty)
    }

    func testActiveSearchPreservesRelevanceOrderOverBrowseSort() {
        let older = Song(
            folderPath: URL(fileURLWithPath: "/tmp/older-match"),
            originalFolderName: "Older Match",
            displayTitle: "Older Neon Match"
        )
        let newer = Song(
            folderPath: URL(fileURLWithPath: "/tmp/newer-weak"),
            originalFolderName: "Newer Weak",
            displayTitle: "Zed Track",
            projectVersions: [
                ProjectVersion(
                    filePath: URL(fileURLWithPath: "/tmp/newer-weak/Newer.cpr"),
                    fileName: "Newer.cpr",
                    modifiedAt: Date(timeIntervalSince1970: 9_999_999)
                )
            ]
        )
        // "neon" should keep Older first by relevance even though Newer has a much newer CPR.
        let state = ArchiveBrowseState(
            songs: [newer, older],
            showHiddenSongs: true,
            selectedShelf: .allSongs,
            selectedCollaboratorID: nil,
            searchQuery: "neon",
            browseFilter: [],
            sortMode: .recentCPR,
            skippedScanEntries: []
        )
        let result = ArchiveBrowseProjection.project(state)
        XCTAssertEqual(result.filteredSongs.map(\.id), [older.id])
    }

    func testShelfHidesIgnoredSongsUnlessShowHiddenEnabled() {
        let visible = Song(
            folderPath: URL(fileURLWithPath: "/tmp/visible"),
            originalFolderName: "Visible",
            displayTitle: "Visible"
        )
        var hidden = Song(
            folderPath: URL(fileURLWithPath: "/tmp/hidden"),
            originalFolderName: "Hidden",
            displayTitle: "Hidden"
        )
        hidden.isIgnored = true
        let state = ArchiveBrowseState(
            songs: [visible, hidden],
            showHiddenSongs: false,
            selectedShelf: .allSongs,
            selectedCollaboratorID: nil,
            searchQuery: "",
            browseFilter: [],
            sortMode: .titleAZ,
            skippedScanEntries: []
        )

        XCTAssertEqual(ArchiveBrowseProjection.project(state).filteredSongs.map(\.id), [visible.id])

        var showingHidden = state
        showingHidden.showHiddenSongs = true
        XCTAssertEqual(
            ArchiveBrowseProjection.project(showingHidden).filteredSongs.map(\.id).sorted(),
            [visible.id, hidden.id].sorted()
        )
    }

    func testSkippedSearchMatchesSurfaceWhenSongsEmpty() {
        let state = ArchiveBrowseState(
            songs: [],
            showHiddenSongs: true,
            selectedShelf: .allSongs,
            selectedCollaboratorID: nil,
            searchQuery: "SecretTakes",
            browseFilter: [],
            sortMode: .titleAZ,
            skippedScanEntries: [
                SkippedScanEntry(
                    kind: .unreadableChild,
                    label: "SecretTakes",
                    reason: "Permission denied"
                )
            ]
        )

        let result = ArchiveBrowseProjection.project(state)
        XCTAssertTrue(result.filteredSongs.isEmpty)
        XCTAssertEqual(result.skippedSearchMatches.count, 1)

        let body = ArchiveSkippedSearchCopy.emptyStateBody(matches: result.skippedSearchMatches)
        XCTAssertTrue(body.contains("SecretTakes"))
        XCTAssertTrue(body.contains("Permission denied"))
        XCTAssertTrue(body.contains("Skipped folders (1)"))
        XCTAssertTrue(body.contains("Settings → Archive"))
    }

    // MARK: - Single-shelf-pass parity (scoped index vs standalone fallback)

    func testScopedIndexMatchesStandaloneAcrossShelvesHiddenFiltersAndQueries() {
        let catalog = makeParityCatalog()
        let filters: [ArchiveBrowseFilter] = [[], [.hasWarnings, .hasStems]]
        for shelf in ArchiveSmartShelf.allCases {
            for showHidden in [false, true] {
                for filter in filters {
                    for query in ["neon", "missing"] {
                        let state = ArchiveBrowseState(
                            songs: catalog,
                            showHiddenSongs: showHidden,
                            selectedShelf: shelf,
                            selectedCollaboratorID: shelf == .byCollaborator ? "collab-1" : nil,
                            searchQuery: query,
                            browseFilter: filter,
                            sortMode: .recentCPR,
                            skippedScanEntries: []
                        )
                        let standalone = ArchiveBrowseProjection.project(state)
                        let scoped = MusicSearchIndex(songs: ArchiveBrowseProjection.shelfSongs(from: state))
                        XCTAssertEqual(
                            ArchiveBrowseProjection.project(state, searchIndex: scoped),
                            standalone,
                            "mismatch shelf=\(shelf) hidden=\(showHidden) filter=\(filter.rawValue) query=\(query)"
                        )
                    }
                }
            }
        }
        // byCollaborator without an ID yields an empty shelf in both paths.
        let nilCollab = ArchiveBrowseState(
            songs: catalog,
            showHiddenSongs: true,
            selectedShelf: .byCollaborator,
            selectedCollaboratorID: nil,
            searchQuery: "neon",
            browseFilter: [],
            sortMode: .recentCPR,
            skippedScanEntries: []
        )
        XCTAssertEqual(
            ArchiveBrowseProjection.project(nilCollab, searchIndex: MusicSearchIndex(songs: ArchiveBrowseProjection.shelfSongs(from: nilCollab))),
            ArchiveBrowseProjection.project(nilCollab)
        )
    }

    func testEmptyQueryIgnoresStaleNarrowSuppliedIndex() {
        let catalog = makeParityCatalog()
        let stale = Song(
            folderPath: URL(fileURLWithPath: "/fixture-only/stale-only"),
            originalFolderName: "Stale Only",
            displayTitle: "Stale Only"
        )
        let state = ArchiveBrowseState(
            songs: catalog,
            showHiddenSongs: false,
            selectedShelf: .allSongs,
            selectedCollaboratorID: nil,
            searchQuery: "   ",
            browseFilter: [.hasWarnings],
            sortMode: .titleAZ,
            skippedScanEntries: []
        )
        XCTAssertEqual(
            ArchiveBrowseProjection.project(state, searchIndex: MusicSearchIndex(songs: [stale])),
            ArchiveBrowseProjection.project(state)
        )
    }

    // MARK: - Fixtures

    private func makeParityCatalog() -> [Song] {
        let now = Date()
        func song(
            _ name: String,
            daysAgo: Double,
            stems: Bool,
            warnings: [String],
            status: ProjectWorkflowStatus?,
            collab: String?,
            hidden: Bool
        ) -> Song {
            let folder = URL(fileURLWithPath: "/fixture-only/\(name)")
            let version = ProjectVersion(
                filePath: folder.appendingPathComponent("\(name).cpr"),
                fileName: "\(name).cpr",
                modifiedAt: now.addingTimeInterval(-daysAgo * 86_400)
            )
            let preview = PreviewCandidate(
                filePath: folder.appendingPathComponent("\(name).wav"),
                fileName: "\(name).wav",
                folderRole: stems ? .stems : .mixdown,
                modifiedAt: now.addingTimeInterval(-daysAgo * 86_400),
                detectedRole: stems ? .stems : .mainMix
            )
            return Song(
                folderPath: folder,
                originalFolderName: name,
                displayTitle: name,
                projectVersions: [version],
                previewCandidates: [preview],
                scanWarnings: warnings,
                collaboratorIDs: collab.map { [$0] } ?? [],
                workflowStatus: status,
                isIgnored: hidden
            )
        }
        return [
            song("Neon Alpha", daysAgo: 5, stems: true, warnings: ["missing preview"], status: .prod, collab: "collab-1", hidden: false),
            song("Neon Beta", daysAgo: 100, stems: false, warnings: [], status: .song, collab: "collab-2", hidden: false),
            song("Ocean Drive", daysAgo: 6, stems: false, warnings: ["missing preview"], status: .done, collab: "collab-1", hidden: false),
            song("Hidden Neon Outtake", daysAgo: 90, stems: true, warnings: ["missing preview"], status: .prod, collab: "collab-1", hidden: true),
        ]
    }
}
