@testable import NikoMusicCore
import XCTest

final class ArchivePhases15to18Tests: XCTestCase {
    func testHasStemsShelf() {
        let folder = URL(fileURLWithPath: "/tmp/stems-song", isDirectory: true)
        let stemPreview = PreviewCandidate(
            filePath: folder.appendingPathComponent("Stems/drums.wav"),
            fileName: "drums.wav",
            folderRole: .stems,
            modifiedAt: Date(),
            detectedRole: .stems
        )
        let withStems = Song(
            folderPath: folder,
            originalFolderName: "Stems Song",
            displayTitle: "Stems Song",
            previewCandidates: [stemPreview]
        )
        let without = Song(
            folderPath: URL(fileURLWithPath: "/tmp/plain", isDirectory: true),
            originalFolderName: "Plain",
            displayTitle: "Plain"
        )
        XCTAssertTrue(withStems.hasStems)
        XCTAssertEqual(ArchiveShelfRanker.hasStems([withStems, without]).map(\.id), [withStems.id])
    }

    func testCollaboratorSearchMatch() {
        var song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/collab", isDirectory: true),
            originalFolderName: "Collab Song",
            displayTitle: "Collab Song"
        )
        song.collaboratorNames = ["Alex Producer"]
        let tokens = MusicSearchMatcher.tokens(from: "alex")
        XCTAssertTrue(MusicSearchMatcher.matches(song: song, queryTokens: tokens))
        let details = MusicSearchMatcher.matchDetails(song: song, queryTokens: tokens)
        XCTAssertEqual(details.first?.kind, .collaborator)
    }

    func testHideSongExcludedFromDefaultShelf() {
        let visible = Song(
            folderPath: URL(fileURLWithPath: "/tmp/a", isDirectory: true),
            originalFolderName: "A",
            displayTitle: "A"
        )
        var hidden = Song(
            folderPath: URL(fileURLWithPath: "/tmp/b", isDirectory: true),
            originalFolderName: "B",
            displayTitle: "B"
        )
        hidden.isIgnored = true
        let filtered = [visible, hidden].filter { !$0.isIgnored }
        XCTAssertEqual(filtered.count, 1)
    }

    func testManualCPROverride() {
        let folder = URL(fileURLWithPath: "/tmp/cpr", isDirectory: true)
        let old = ProjectVersion(
            filePath: folder.appendingPathComponent("old.cpr"),
            fileName: "old.cpr",
            modifiedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = ProjectVersion(
            filePath: folder.appendingPathComponent("new.cpr"),
            fileName: "new.cpr",
            modifiedAt: Date(timeIntervalSince1970: 2_000)
        )
        let scanned = Song(
            folderPath: folder,
            originalFolderName: "CPR",
            displayTitle: "CPR",
            projectVersions: [old, newer],
            latestCPR: newer
        )
        let metadata = SongUserMetadata(
            songID: scanned.id,
            cprSelectionMode: .manual,
            manualMainCPRID: old.id
        )
        let merged = ArchiveMetadataMerger.merge(scanned: scanned, metadata: metadata)
        XCTAssertEqual(merged.effectiveLatestCPR?.id, old.id)
    }

    func testSortTitleAZ() {
        let b = Song(folderPath: URL(fileURLWithPath: "/tmp/b", isDirectory: true), originalFolderName: "b", displayTitle: "Bravo")
        let a = Song(folderPath: URL(fileURLWithPath: "/tmp/a", isDirectory: true), originalFolderName: "a", displayTitle: "Alpha")
        let sorted = ArchiveBrowseSortMode.sort([b, a], mode: .titleAZ)
        XCTAssertEqual(sorted.map(\.displayTitle), ["Alpha", "Bravo"])
    }

    func testBrowseFilterNoPreview() {
        let withPreview = Song(
            folderPath: URL(fileURLWithPath: "/tmp/p", isDirectory: true),
            originalFolderName: "p",
            displayTitle: "p",
            mainPreviewCandidateID: "x"
        )
        let without = Song(
            folderPath: URL(fileURLWithPath: "/tmp/n", isDirectory: true),
            originalFolderName: "n",
            displayTitle: "n"
        )
        let filtered = ArchiveBrowseFilter.apply([withPreview, without], filter: .noPreview)
        XCTAssertEqual(filtered.map(\.displayTitle), ["n"])
    }

    func testNewSongCreator() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-song-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let song = try NewSongFolderCreator.create(
            request: NewSongRequest(name: "Fresh Track", root: root, appNote: "seed")
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: song.folderPath.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: song.folderPath.appendingPathComponent("Mixdown", isDirectory: true).path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: song.folderPath.appendingPathComponent("Stems", isDirectory: true).path
        ))
    }

    func testNewSongCreatorRejectsNamesThatEscapeDestinationRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-song-contained-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try NewSongFolderCreator.create(
                request: NewSongRequest(name: "../Outside", root: root)
            )
        ) { error in
            XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .invalidName)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.deletingLastPathComponent().appendingPathComponent("Outside").path
        ))
    }

    func testExportIndexJSON() throws {
        let song = Song(
            folderPath: URL(fileURLWithPath: "/tmp/export", isDirectory: true),
            originalFolderName: "Export",
            displayTitle: "Export"
        )
        let root = URL(fileURLWithPath: "/tmp/root", isDirectory: true)
        let data = try ArchiveIndexExporter.exportJSON(roots: [root], songs: [song])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ArchiveIndexExport.self, from: data)
        XCTAssertEqual(decoded.songCount, 1)
        XCTAssertEqual(decoded.songs.first?.displayTitle, "Export")
    }

    func testCollaboratorStoreRoundtrip() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collab-\(UUID().uuidString).sqlite")
        let store = try SQLiteCollaboratorStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let collaborator = Collaborator(displayName: "Jamie")
        try store.upsert(collaborator)
        let loaded = try store.loadAll()
        XCTAssertEqual(loaded.map(\.displayName), ["Jamie"])
    }

    func testMetadataRoundtripExtendedFields() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("meta-ext-\(UUID().uuidString).sqlite")
        let store = try SQLiteSongUserMetadataStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        let metadata = SongUserMetadata(
            songID: "/tmp/song",
            collaboratorIDs: ["c1"],
            isIgnored: true,
            cprSelectionMode: .manual,
            manualMainCPRID: "cpr-1",
            ignoredCPRVersionIDs: ["cpr-2"]
        )
        try store.upsert(metadata)
        let loaded = try XCTUnwrap(try store.loadAll()["/tmp/song"])
        XCTAssertEqual(loaded.collaboratorIDs, ["c1"])
        XCTAssertTrue(loaded.isIgnored)
        XCTAssertEqual(loaded.cprSelectionMode, .manual)
        XCTAssertEqual(loaded.manualMainCPRID, "cpr-1")
        XCTAssertEqual(loaded.ignoredCPRVersionIDs, ["cpr-2"])
    }
}
