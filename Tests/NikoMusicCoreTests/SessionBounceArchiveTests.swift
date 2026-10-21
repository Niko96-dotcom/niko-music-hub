import XCTest
@testable import NikoMusicCore

final class SessionBounceArchiveTests: XCTestCase {
    private let deliveries = [
        (folder: "HENRY DAY 1 ", project: "HENRY DAY 1", file: "sun stays up forever session bounce henry x hailex x niko.wav", title: "Sun Stays Up Forever"),
        (folder: "HENRY DAY 1 IDEA 2", project: "HENRY DAY 2", file: "i said i love you first session bounce henry x hailey x niko.wav", title: "I Said I Love You First"),
    ]

    func testTrailingSpaceAndSharedFolderPrefixKeepPreviewsInTheirOwnSong() throws {
        let root = try makeArchive()
        let scanner = MusicArchiveScanner()
        let full = try scanner.scan(roots: [root])
        XCTAssertTrue(full.globalWarnings.isEmpty)
        XCTAssertTrue(full.skippedEntries.isEmpty)
        XCTAssertEqual(full.songs.count, 2)
        XCTAssertEqual(Set(full.songs.map(\.id)).count, 2)
        XCTAssertEqual(SongCatalogDeduplicator.uniqueByID(full.songs + full.songs), full.songs)
        try assertOwnPreviews(full.songs, root: root)

        for delivery in deliveries {
            let folder = root.appendingPathComponent(delivery.folder, isDirectory: true)
            let changed = folder.appendingPathComponent(delivery.file)
            let resolution = ArchiveSongFolderResolver.resolve(changedPaths: [changed], roots: [root])
            XCTAssertEqual(resolution.songFolders, [folder])
            XCTAssertTrue(resolution.rootsForRootLevelScan.isEmpty)
            let incremental = try scanner.scanIncremental(resolution: resolution, roots: [root])
            XCTAssertEqual(incremental.songs, full.songs.filter { $0.originalFolderName == delivery.folder })
        }

        let decoded = try JSONDecoder().decode([Song].self, from: JSONEncoder().encode(full.songs))
        try assertOwnPreviews(PreviewAutoSelectionNormalizer.normalized(decoded), root: root)
    }

    func testSessionBounceCollaboratorSuffixSuppliesTitleAheadOfAbletonWorkingName() throws {
        let root = try makeArchive()
        let songs = try MusicArchiveScanner().scan(roots: [root]).songs
        for delivery in deliveries {
            let song = try XCTUnwrap(songs.first { $0.originalFolderName == delivery.folder })
            XCTAssertEqual(song.displayTitle, delivery.title)

            var cached = song
            cached.displayTitle = delivery.folder
            let renamed = ArchiveMetadataMerger.merge(
                scanned: cached,
                metadata: SongUserMetadata(songID: song.id, virtualTitle: "My title")
            )
            let refreshed = PreviewAutoSelectionNormalizer.normalizedForLaunch([renamed], snapshotVersion: 1)
            XCTAssertEqual(refreshed.first?.displayTitle, delivery.title)
            XCTAssertEqual(refreshed.first?.effectiveDisplayTitle, "My title")
        }
    }

    private func assertOwnPreviews(_ songs: [Song], root: URL) throws {
        for delivery in deliveries {
            let song = try XCTUnwrap(songs.first { $0.originalFolderName == delivery.folder })
            let folder = root.appendingPathComponent(delivery.folder, isDirectory: true)
            let preview = try XCTUnwrap(song.previewCandidates.first)
            XCTAssertEqual(song.id, folder.standardizedFileURL.path)
            XCTAssertEqual(song.folderPath.path, folder.path)
            XCTAssertEqual(song.previewCandidates.count, 1, "Ableton .asd sidecars are not audio")
            XCTAssertEqual(preview.fileName, delivery.file)
            XCTAssertEqual(preview.filePath.path, folder.appendingPathComponent(delivery.file).path)
            XCTAssertEqual(preview.folderRole, .root)
            XCTAssertEqual(preview.durationSeconds, 30)
            XCTAssertEqual(song.mainPreviewCandidateID, preview.id)
            XCTAssertEqual(song.mainPreviewURL, preview.filePath)
            XCTAssertEqual(song.projectVersions.map(\.fileName), [delivery.project + ".als"])
        }
    }

    private func makeArchive() throws -> URL {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/session-bounce-\(UUID())", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        for (index, delivery) in deliveries.enumerated() {
            let folder = root.appendingPathComponent(delivery.folder, isDirectory: true)
            let project = folder.appendingPathComponent(delivery.project + " Project", isDirectory: true)
            for subfolder in ["Backup", "Samples", "Ableton Project Info"] {
                try fm.createDirectory(at: project.appendingPathComponent(subfolder), withIntermediateDirectories: true)
            }
            try Data("<Ableton/>".utf8).write(to: project.appendingPathComponent(delivery.project + ".als"))
            try Data().write(to: project.appendingPathComponent("Icon\r"))
            try Self.silentWAV().write(to: folder.appendingPathComponent(delivery.file))
            let sidecar = index == 0
                ? "sun stays up for ever session bounce henry x hailex x niko.wav.asd"
                : delivery.file + ".asd"
            try Data("Ableton analysis".utf8).write(to: folder.appendingPathComponent(sidecar))
        }
        return root
    }

    private static func silentWAV() -> Data {
        func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        let payload = Data(count: 8000 * 2 * 30)
        var data = Data("RIFF".utf8) + le32(UInt32(36 + payload.count)) + Data("WAVEfmt ".utf8) + le32(16)
        data += le16(1) + le16(1) + le32(8000) + le32(16000) + le16(2) + le16(16)
        return data + Data("data".utf8) + le32(UInt32(payload.count)) + payload
    }
}
