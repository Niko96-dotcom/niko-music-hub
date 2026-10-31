import CryptoKit
import SQLite3
import XCTest
@testable import NikoMusicCore

/// The launch load skips re-ranking previews when the snapshot was written with the current preview
/// semantics. That is only safe while (1) the skip gives the same songs as a full refresh and (2) any
/// change to what a scan derives bumps `PreviewAutoSelectionNormalizer.currentVersion`.
final class PreviewSemanticsVersionTests: XCTestCase {
    /// The digest of the fixture archive's derived preview data under `currentVersion`. When this test
    /// fails, detection, ranking or title resolution changed: bump `currentVersion` and record the new
    /// digest here, so cached snapshots from the old logic are refreshed at launch.
    private static let recordedDigests: [Int: String] = [
        1: "3f720db896b897d609fbc1671f9065993b0b7710fb1cbd8424266c6f126ae9fd",
        2: "3f720db896b897d609fbc1671f9065993b0b7710fb1cbd8424266c6f126ae9fd",
        // A bounce in its own export folder names the song; the fixture has none.
        3: "3f720db896b897d609fbc1671f9065993b0b7710fb1cbd8424266c6f126ae9fd",
    ]

    private func scannedFixtureSongs() throws -> [Song] {
        try CubaseFixtures.ensureGenerated()
        return try MusicArchiveScanner().scan(roots: [CubaseFixtures.archiveRoot]).songs
    }

    func testDerivedPreviewDataMatchesTheRecordedVersion() throws {
        let songs = try scannedFixtureSongs()
        XCTAssertFalse(songs.isEmpty)
        let lines = songs.sorted { $0.originalFolderName < $1.originalFolderName }.map { song -> String in
            let main = song.previewCandidates.first { $0.id == song.mainPreviewCandidateID }?.fileName ?? "-"
            let candidates = song.previewCandidates.map { candidate in
                "\(candidate.fileName):\(candidate.folderRole):\(candidate.detectedRole):"
                    + String(format: "%.3f", candidate.confidenceScore)
            }
            return ([song.originalFolderName, song.displayTitle, main] + candidates).joined(separator: "|")
        }
        let digest = SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(
            digest, Self.recordedDigests[PreviewAutoSelectionNormalizer.currentVersion],
            "Preview semantics changed: bump PreviewAutoSelectionNormalizer.currentVersion and record \(digest)"
        )
    }

    /// A song whose title comes from its top preview (a named delivery in a generic session folder), so
    /// hiding that preview changes the title: the case a blanket skip of the launch refresh gets wrong.
    private func titleFromPreviewSong() throws -> Song {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NMH-SemanticsTitle-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Session Twelve", isDirectory: true)
        try fm.createDirectory(at: folder.appendingPathComponent("Mixdown"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: folder.appendingPathComponent("Session Twelve.cpr"))
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        for (offset, name) in [(200.0, "Bright Lights mix.wav"), (100.0, "Night Drive mix.wav")] {
            let file = folder.appendingPathComponent("Mixdown/\(name)")
            try Self.silentWAV(seconds: 30).write(to: file)
            try fm.setAttributes([.modificationDate: epoch.addingTimeInterval(offset)], ofItemAtPath: file.path)
        }
        return try XCTUnwrap(MusicArchiveScanner().scan(roots: [root]).songs.first)
    }

    private static func silentWAV(seconds: Int) -> Data {
        func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        let payload = Data(count: 44_100 * 2 * seconds)
        var data = Data("RIFF".utf8) + le32(UInt32(36 + payload.count)) + Data("WAVEfmt ".utf8) + le32(16)
        data += le16(1) + le16(1) + le32(44_100) + le32(88_200) + le16(2) + le16(16)
        return data + Data("data".utf8) + le32(UInt32(payload.count)) + payload
    }

    func testHidingTheTitlePreviewIsRefreshedAtLaunch() throws {
        let song = try titleFromPreviewSong()
        let top = try XCTUnwrap(song.previewCandidates.first { $0.id == song.mainPreviewCandidateID })
        let merged = ArchiveMetadataMerger.merge(
            scanned: [song], metadataByID: [song.id: SongUserMetadata(songID: song.id, ignoredPreviewCandidateIDs: [top.id])]
        )
        let full = PreviewAutoSelectionNormalizer.normalized(merged)
        XCTAssertNotEqual(full.first?.displayTitle, song.displayTitle, "fixture must take its title from the hidden preview")
        XCTAssertEqual(
            PreviewAutoSelectionNormalizer.normalizedForLaunch(merged, snapshotVersion: PreviewAutoSelectionNormalizer.currentVersion),
            full
        )
    }

    func testLaunchLoadEqualsAFullRefresh() throws {
        let scanned = try scannedFixtureSongs()
        // User metadata as the launch merge applies it: hidden previews on some songs, a manual pick on one.
        var metadata: [String: SongUserMetadata] = [:]
        for (index, song) in scanned.enumerated() where song.previewCandidates.count > 1 {
            if index % 2 == 0 {
                metadata[song.id] = SongUserMetadata(songID: song.id, ignoredPreviewCandidateIDs: [song.previewCandidates[0].id])
            } else {
                metadata[song.id] = SongUserMetadata(
                    songID: song.id, previewSelectionMode: .manual, manualMainPreviewID: song.previewCandidates.last?.id
                )
            }
        }
        XCTAssertTrue(metadata.values.contains { !$0.ignoredPreviewCandidateIDs.isEmpty }, "fixture needs hidden previews")
        let merged = ArchiveMetadataMerger.merge(scanned: scanned, metadataByID: metadata)
        let full = PreviewAutoSelectionNormalizer.normalized(merged)
        let current = PreviewAutoSelectionNormalizer.normalizedForLaunch(
            merged, snapshotVersion: PreviewAutoSelectionNormalizer.currentVersion
        )
        XCTAssertEqual(current, full)
        XCTAssertEqual(PreviewAutoSelectionNormalizer.normalizedForLaunch(merged, snapshotVersion: nil), full)
        XCTAssertEqual(PreviewAutoSelectionNormalizer.normalizedForLaunch(scanned, snapshotVersion: 0), PreviewAutoSelectionNormalizer.normalized(scanned))
    }

    func testOldDatabasesGainTheColumnAndRoundTripTheVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NMH-SemanticsVersion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("archive-index.sqlite")

        // A database from before the version existed: the meta table has no version column.
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let legacy = """
        CREATE TABLE archive_snapshot_meta (id INTEGER PRIMARY KEY CHECK (id = 1), roots_json TEXT NOT NULL, scanned_at TEXT NOT NULL);
        CREATE TABLE archive_snapshot_song (song_id TEXT PRIMARY KEY, song_json TEXT NOT NULL, position INTEGER NOT NULL);
        INSERT INTO archive_snapshot_meta (id, roots_json, scanned_at) VALUES (1, '["/Archive"]', '2026-10-01T10:00:00Z');
        """
        XCTAssertEqual(sqlite3_exec(db, legacy, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let song = try XCTUnwrap(try scannedFixtureSongs().first)
        let store = try SQLiteArchiveIndexStore(databaseURL: url)
        // The legacy meta row has no songs yet; after a save without a version the load reports none.
        try store.save(ArchiveIndexSnapshot(roots: ["/Archive"], songs: [song], scannedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        XCTAssertNil(try store.loadLatest()?.previewSemanticsVersion)

        try store.save(ArchiveIndexSnapshot(
            roots: ["/Archive"], songs: [song], scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
            previewSemanticsVersion: PreviewAutoSelectionNormalizer.currentVersion
        ))
        let reopened = try SQLiteArchiveIndexStore(databaseURL: url)
        let loaded = try XCTUnwrap(try reopened.loadLatest())
        XCTAssertEqual(loaded.previewSemanticsVersion, PreviewAutoSelectionNormalizer.currentVersion)
        XCTAssertEqual(loaded.songs, [song])
    }
}
