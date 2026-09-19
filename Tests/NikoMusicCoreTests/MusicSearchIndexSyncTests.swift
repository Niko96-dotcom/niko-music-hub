import XCTest
@testable import NikoMusicCore

final class MusicSearchIndexSyncTests: XCTestCase {
    private func makeSong(
        title: String,
        folder: String? = nil,
        aliases: [String] = [],
        collaborators: [String] = [],
        appNote: String? = nil,
        sidecarNotes: String? = nil,
        warnings: [String] = [],
        workflow: ProjectWorkflowStatus? = nil
    ) -> Song {
        Song(
            folderPath: URL(fileURLWithPath: "/sync-only/\(folder ?? title)"),
            originalFolderName: folder ?? title,
            displayTitle: title,
            scanWarnings: warnings,
            sidecarNotes: sidecarNotes,
            aliases: aliases,
            appNote: appNote,
            collaboratorNames: collaborators,
            workflowStatus: workflow
        )
    }

    func testSyncMatchesRebuildParity() {
        let songs = [
            makeSong(title: "Neon Hook", aliases: ["Demo"], collaborators: ["Maria Klein"]),
            makeSong(title: "Ocean Drive"),
            makeSong(title: "GLÜHWURM"),
        ]
        var viaSync = MusicSearchIndex()
        viaSync.sync(from: songs)
        let viaInit = MusicSearchIndex(songs: songs)
        var viaRebuild = MusicSearchIndex()
        viaRebuild.rebuild(from: songs)
        for query in ["neon", "neon hook", "ocean", "gluhwurm", "maria", "zzzz absent"] {
            for index in [viaSync, viaInit, viaRebuild] {
                let results = index.searchResults(query)
                let expected = viaInit.searchResults(query)
                XCTAssertEqual(results.map(\.song.id), expected.map(\.song.id), query)
                XCTAssertEqual(results.map(\.score), expected.map(\.score), query)
                XCTAssertEqual(results.map(\.matchSummary), expected.map(\.matchSummary), query)
            }
        }
        XCTAssertEqual(viaSync.songs, songs)
    }

    func testSyncReflectsTitleAliasFolderAndMetadataEdits() {
        // Folder intentionally distinct from the title so title invalidation
        // is observable (folder text would otherwise still match "neon").
        let base = makeSong(
            title: "Neon Hook",
            folder: "Studio Alpha",
            aliases: ["Working Demo"],
            collaborators: ["Maria Klein"],
            appNote: "Final vocal",
            sidecarNotes: "Chorus idea",
            warnings: ["Missing preview"],
            workflow: .song
        )
        var index = MusicSearchIndex()
        index.sync(from: [base])
        XCTAssertEqual(index.search("neon").count, 1)

        // Title edit invalidates.
        var renamed = base
        renamed.virtualTitle = "Ocean Drive Two"
        index.sync(from: [renamed])
        XCTAssertTrue(index.search("neon").isEmpty)
        XCTAssertEqual(index.search("ocean drive two").count, 1)

        // Alias edit invalidates.
        var aliasEdit = renamed
        aliasEdit.aliases = ["Unique Alias ZZ"]
        index.sync(from: [aliasEdit])
        XCTAssertEqual(index.search("unique alias").count, 1)
        XCTAssertTrue(index.search("working demo").isEmpty)

        // Folder edit invalidates.
        var folderEdit = aliasEdit
        folderEdit = Song(
            folderPath: aliasEdit.folderPath,
            originalFolderName: "Unique Folder ZZ",
            displayTitle: aliasEdit.displayTitle,
            scanWarnings: aliasEdit.scanWarnings,
            sidecarNotes: aliasEdit.sidecarNotes,
            mainPreviewCandidateID: aliasEdit.mainPreviewCandidateID,
            latestCPR: aliasEdit.latestCPR,
            virtualTitle: aliasEdit.virtualTitle,
            aliases: aliasEdit.aliases,
            appNote: aliasEdit.appNote,
            collaboratorNames: aliasEdit.collaboratorNames,
            workflowStatus: aliasEdit.workflowStatus
        )
        index.sync(from: [folderEdit])
        XCTAssertEqual(index.search("unique folder").count, 1)

        // Metadata (app note / workflow) edits invalidate.
        var noteEdit = folderEdit
        noteEdit.appNote = "Completely Different Note ZZ"
        noteEdit.workflowStatus = .done
        index.sync(from: [noteEdit])
        XCTAssertEqual(index.search("completely different").count, 1)
        XCTAssertEqual(index.search("done").count, 1)
    }

    func testSyncReturnsFreshSongForNonSearchMetadataWithoutChangingRanking() {
        var song = makeSong(title: "Neon Hook", collaborators: ["Maria Klein"])
        song.collaboratorIDs = ["id-1"]
        var index = MusicSearchIndex()
        index.sync(from: [song])
        let before = index.searchResults("neon")
        XCTAssertEqual(before.count, 1)

        // Non-searchable changes: collaborator IDs (names unchanged),
        // selection modes, and version timestamps must not change ranking
        // but the returned Song values must be fresh.
        var updated = song
        updated.collaboratorIDs = ["id-2"]
        updated.previewSelectionMode = .manual
        updated.ignoredPreviewCandidateIDs = ["ignored"]
        updated.cprSelectionMode = .manual
        var versioned = ProjectVersion(
            filePath: URL(fileURLWithPath: "/sync-only/Neon Hook/take.cpr"),
            fileName: "take.cpr",
            modifiedAt: .distantPast
        )
        updated.projectVersions = [versioned]
        index.sync(from: [updated])
        // Bump only the timestamp (filename searchable text unchanged).
        versioned = ProjectVersion(
            filePath: URL(fileURLWithPath: "/sync-only/Neon Hook/take.cpr"),
            fileName: "take.cpr",
            modifiedAt: Date(timeIntervalSince1970: 9_999_999)
        )
        var restamped = updated
        restamped.projectVersions = [versioned]
        index.sync(from: [restamped])

        let after = index.searchResults("neon")
        XCTAssertEqual(after.map(\.song.id), before.map(\.song.id))
        XCTAssertEqual(after.map(\.score), before.map(\.score))
        XCTAssertEqual(after.map(\.matchSummary), before.map(\.matchSummary))
        XCTAssertEqual(after.first?.song.collaboratorIDs, ["id-2"])
        XCTAssertEqual(after.first?.song.previewSelectionMode, .manual)
        XCTAssertEqual(after.first?.song.projectVersions.first?.modifiedAt, versioned.modifiedAt)
    }

    func testSyncDropsRemovedSongsAndHandlesReordering() {
        let neon = makeSong(title: "Neon Hook")
        let ocean = makeSong(title: "Ocean Drive")
        let silver = makeSong(title: "Silver Lining")
        var index = MusicSearchIndex()
        index.sync(from: [neon, ocean, silver])
        XCTAssertEqual(index.search("neon").count, 1)

        // Removal drops the id: bounded to the live shelf.
        index.sync(from: [ocean, silver])
        XCTAssertTrue(index.search("neon").isEmpty)
        XCTAssertEqual(index.songs.map(\.id), [ocean.id, silver.id])
        XCTAssertEqual(index.search("ocean").first?.displayTitle, "Ocean Drive")

        // Reordering keeps fresh values and identical relevance results.
        index.sync(from: [silver, ocean])
        XCTAssertEqual(index.songs.map(\.id), [silver.id, ocean.id])
        XCTAssertEqual(index.search("ocean").first?.displayTitle, "Ocean Drive")
        XCTAssertEqual(index.search("silver").first?.displayTitle, "Silver Lining")
    }

    func testSyncEmptyClearsBoundedMemory() {
        var index = MusicSearchIndex()
        index.sync(from: [makeSong(title: "Neon Hook")])
        XCTAssertFalse(index.songs.isEmpty)
        index.sync(from: [])
        XCTAssertTrue(index.songs.isEmpty)
        XCTAssertTrue(index.search("neon").isEmpty)
    }
}
