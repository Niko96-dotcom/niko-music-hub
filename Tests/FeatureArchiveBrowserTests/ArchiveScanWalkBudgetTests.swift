import Foundation
@testable import FeatureArchiveBrowser
@testable import NikoMusicCore
import XCTest

/// Filesystem-call budget and wall-time harness for archive scans and FSEvents-driven
/// incremental updates. Always runs on a small synthetic archive and asserts the budget;
/// set `NMH_ARCHIVE_SCAN_BENCH_SONGS=3000` to print numbers for a large archive.
/// Every archive here is built under a fresh temporary directory; no real music is read.
final class ArchiveScanWalkBudgetTests: XCTestCase {
    private var archive: SyntheticArchive!

    override func setUpWithError() throws {
        archive = try SyntheticArchive.make(songCount: Self.songCount)
    }

    override func tearDownWithError() throws {
        archive?.remove()
    }

    private static var songCount: Int {
        ProcessInfo.processInfo.environment["NMH_ARCHIVE_SCAN_BENCH_SONGS"].flatMap(Int.init) ?? 120
    }

    func testFullScanWalksEachSongFolderOnce() throws {
        let fileManager = CountingFileManager()
        let start = Date()
        let result = try MusicArchiveScanner(fileManager: fileManager).scan(roots: [archive.root])
        let elapsed = Date().timeIntervalSince(start)
        let counts = fileManager.snapshot()
        let folderSongs = archive.songFolders.count

        report("full scan", songs: folderSongs, elapsed: elapsed, counts: counts)
        XCTAssertEqual(result.songs.filter { $0.previewCandidates.isEmpty == false }.count, folderSongs)
        // One recursive walk per song folder feeds both project and preview detection.
        XCTAssertEqual(counts.enumerators, folderSongs)
    }

    @MainActor
    func testIncrementalBatchForOneSongOnlyTouchesThatSong() throws {
        let existing = try MusicArchiveScanner().scan(roots: [archive.root]).songs
        let target = archive.songFolders[archive.songFolders.count / 2]
        let changed = [target.appendingPathComponent("\(target.lastPathComponent) v2.cpr")]

        let fileManager = CountingFileManager()
        let start = Date()
        let resolution = ArchiveSongFolderResolver.resolve(
            changedPaths: changed, roots: [archive.root], fileManager: fileManager
        )
        let incremental = try MusicArchiveScanner(fileManager: fileManager)
            .scanIncremental(resolution: resolution, roots: [archive.root])
        let affected = Set(resolution.songFolders.map { $0.standardizedFileURL.path })
        let statsBeforeMerge = fileManager.snapshot().fileExists
        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: existing,
            incremental: incremental,
            affectedSongIDs: affected,
            fileManager: fileManager,
            unaffectedSongFoldersMayHaveMoved: ArchiveSongFolderResolver.mayMoveSongFolders(
                changedPaths: changed, roots: [archive.root]
            )
        )
        let elapsed = Date().timeIntervalSince(start)
        let counts = fileManager.snapshot()

        report("incremental 1-song batch", songs: existing.count, elapsed: elapsed, counts: counts)
        assertSameCatalog(merged, existing)
        XCTAssertEqual(counts.enumerators, 1)
        XCTAssertEqual(counts.fileExists, statsBeforeMerge, "the merge must not stat songs outside the batch")
    }

    @MainActor
    func testIncrementalRenameStillVerifiesSiblingFolders() throws {
        let existing = try MusicArchiveScanner().scan(roots: [archive.root]).songs
        let old = archive.songFolders[0]
        let renamed = archive.root.appendingPathComponent("Renamed Song", isDirectory: true)
        try FileManager.default.moveItem(at: old, to: renamed)
        // Finder-style: only the new name is reported.
        let changed = [renamed]

        let fileManager = CountingFileManager()
        let resolution = ArchiveSongFolderResolver.resolve(changedPaths: changed, roots: [archive.root])
        let incremental = try MusicArchiveScanner().scanIncremental(resolution: resolution, roots: [archive.root])
        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: existing,
            incremental: incremental,
            affectedSongIDs: Set(resolution.songFolders.map { $0.standardizedFileURL.path }),
            fileManager: fileManager,
            unaffectedSongFoldersMayHaveMoved: ArchiveSongFolderResolver.mayMoveSongFolders(
                changedPaths: changed, roots: [archive.root]
            )
        )

        XCTAssertFalse(merged.contains { $0.id == old.standardizedFileURL.path })
        XCTAssertTrue(merged.contains { $0.id == renamed.standardizedFileURL.path })
        XCTAssertEqual(merged.count, existing.count)
        XCTAssertGreaterThanOrEqual(fileManager.snapshot().fileExists, existing.count - 1)
    }

    private func report(_ label: String, songs: Int, elapsed: TimeInterval, counts: CountingFileManager.Counts) {
        let perSong = Double(counts.enumeratedEntries) / Double(max(songs, 1))
        print(String(
            format: "[scan-budget] %@: songs=%d wall=%.3fs enumerators=%d entries=%d (%.1f/song) "
                + "contentsOfDirectory=%d fileExists=%d",
            label, songs, elapsed, counts.enumerators, counts.enumeratedEntries, perSong,
            counts.contentsOfDirectory, counts.fileExists
        ))
    }
}

/// Scan output must be identical to composing the standalone project and preview detectors,
/// which is what the scanner did before it shared one walk per song folder.
final class ArchiveScanEquivalenceTests: XCTestCase {
    func testSyntheticArchiveMatchesStandaloneDetectors() throws {
        let archive = try SyntheticArchive.make(songCount: 60)
        defer { archive.remove() }
        try assertScanMatchesStandaloneDetectors(root: archive.root)
    }

    func testFixtureArchiveMatchesStandaloneDetectors() throws {
        try CubaseFixtures.ensureGenerated()
        try assertScanMatchesStandaloneDetectors(root: CubaseFixtures.archiveRoot)
        try assertScanMatchesStandaloneDetectors(root: CubaseFixtures.summaryTruncationRoot)
    }

    func testIncrementalScanMatchesFullScanForEverySong() throws {
        let archive = try SyntheticArchive.make(songCount: 40)
        defer { archive.remove() }
        let full = try MusicArchiveScanner().scan(roots: [archive.root])
        let resolution = ArchiveSongFolderResolver.Resolution(songFolders: Set(archive.songFolders))
        let incremental = try MusicArchiveScanner().scanIncremental(resolution: resolution, roots: [archive.root])
        let fullFolderSongs = full.songs.filter { archive.songFolders.map(\.standardizedFileURL.path).contains($0.id) }
        assertSameCatalog(incremental.songs, fullFolderSongs)
    }

    private func assertScanMatchesStandaloneDetectors(root: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let result = try MusicArchiveScanner().scan(roots: [root])
        XCTAssertFalse(result.songs.isEmpty, file: file, line: line)
        var compared = 0
        for song in result.songs {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: song.folderPath.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let expected = try Self.referenceSong(folder: song.folderPath)
            XCTAssertEqual(song.id, expected.id, file: file, line: line)
            XCTAssertEqual(song.displayTitle, expected.displayTitle, song.id, file: file, line: line)
            XCTAssertEqual(song.projectVersions, expected.projectVersions, song.id, file: file, line: line)
            XCTAssertEqual(song.latestCPR, expected.latestCPR, song.id, file: file, line: line)
            XCTAssertEqual(song.previewCandidates, expected.previewCandidates, song.id, file: file, line: line)
            XCTAssertEqual(song.mainPreviewCandidateID, expected.mainPreviewCandidateID, song.id, file: file, line: line)
            XCTAssertEqual(song.scanWarnings, expected.scanWarnings, song.id, file: file, line: line)
            XCTAssertEqual(song.sidecarNotes, expected.sidecarNotes, song.id, file: file, line: line)
            XCTAssertEqual(song, expected, song.id, file: file, line: line)
            compared += 1
        }
        XCTAssertGreaterThan(compared, 0, file: file, line: line)
    }

    /// The pre-change `scanSongFolder`: two independent walks composed by the ranker.
    private static func referenceSong(folder: URL) throws -> Song {
        let versions = try ProjectVersionDetector().detectVersions(in: folder)
        let ranker = PreviewConfidenceRanker()
        let ranked = ranker.rank(
            try PreviewCandidateDetector().detectCandidates(in: folder),
            projectContext: PreviewRankingProjectContext.from(projectVersions: versions)
        )
        return Song(
            folderPath: folder,
            originalFolderName: folder.lastPathComponent,
            displayTitle: SongTitleResolver().displayTitle(
                fromFolderName: folder.lastPathComponent,
                mainPreview: ranked.first,
                projectVersions: versions
            ),
            projectVersions: versions,
            previewCandidates: ranked,
            scanWarnings: versions.isEmpty ? ["No project files (.cpr or .als) found"] : [],
            sidecarNotes: SidecarNotesReader().readNotes(in: folder),
            mainPreviewCandidateID: ranker.mainPreviewID(from: ranked),
            latestCPR: ProjectVersionDetector().latestProject(from: versions)
        )
    }
}

/// Field-by-field catalog comparison. Folder URLs compare by standardized path: a folder URL
/// built with `isDirectory: true` carries a trailing slash that is not a catalog difference.
func assertSameCatalog(_ actual: [Song], _ expected: [Song], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.map(\.id), expected.map(\.id), file: file, line: line)
    for (lhs, rhs) in zip(actual, expected) where lhs.id == rhs.id {
        XCTAssertEqual(lhs.folderPath.standardizedFileURL.path, rhs.folderPath.standardizedFileURL.path, lhs.id, file: file, line: line)
        XCTAssertEqual(lhs.originalFolderName, rhs.originalFolderName, lhs.id, file: file, line: line)
        XCTAssertEqual(lhs.displayTitle, rhs.displayTitle, lhs.id, file: file, line: line)
        XCTAssertEqual(lhs.projectVersions, rhs.projectVersions, lhs.id, file: file, line: line)
        XCTAssertEqual(lhs.latestCPR, rhs.latestCPR, lhs.id, file: file, line: line)
        XCTAssertEqual(lhs.previewCandidates, rhs.previewCandidates, lhs.id, file: file, line: line)
        XCTAssertEqual(lhs.mainPreviewCandidateID, rhs.mainPreviewCandidateID, lhs.id, file: file, line: line)
        XCTAssertEqual(lhs.scanWarnings, rhs.scanWarnings, lhs.id, file: file, line: line)
        XCTAssertEqual(lhs.sidecarNotes, rhs.sidecarNotes, lhs.id, file: file, line: line)
    }
}

// MARK: - Synthetic archive

struct SyntheticArchive {
    let base: URL
    let root: URL
    let songFolders: [URL]

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }

    /// Tiny placeholder files shaped like a Cubase archive: versions, auto-saves, a Mixdown
    /// folder, an Audio folder and edge cases (Ableton backups, `.bak`, a folder named like a
    /// project, symlinks leaving the song) spread across songs. Mtimes are fixed.
    static func make(songCount: Int) throws -> SyntheticArchive {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("nmh-scan-budget-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Archive", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try wav.write(to: outside.appendingPathComponent("Escaped.wav"))

        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        var folders: [URL] = []
        for index in 0..<songCount {
            let name = String(format: "Song %04d", index)
            let folder = root.appendingPathComponent(name, isDirectory: true)
            var files: [(String, Data)] = [
                ("\(name) v1.cpr", placeholder),
                ("\(name) v2.cpr", placeholder),
                ("\(name) v2.bak.cpr", placeholder),
                ("Auto Saves/\(name)-01.bak", placeholder),
                ("Mixdown/\(name) v2 mix.wav", wav),
                ("Mixdown/\(name) v1 master.wav", wav),
                ("Audio/Audio 01.wav", wav),
                ("Audio/Audio 02.wav", wav),
                ("Stems/Drums.wav", wav)
            ]
            if index % 5 == 0 { files.append(("Mixdown/\(name) v1.mp3", placeholder)) }
            if index % 7 == 0 { files.append(("notes.txt", Data("Idea \(index)".utf8))) }
            if index % 11 == 0 {
                files.append(("\(name) Live.als", placeholder))
                files.append(("Backup/\(name) Live [2024].als", placeholder))
            }
            if index % 13 == 0 { files.append(("Folder.cpr/Inside.wav", wav)) }
            for (offset, (relative, data)) in files.enumerated() {
                let url = folder.appendingPathComponent(relative)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
                let mtime = epoch.addingTimeInterval(Double(index * 100 + (offset * 7) % 19))
                try fm.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
            }
            if index % 17 == 0 {
                try fm.createSymbolicLink(
                    at: folder.appendingPathComponent("Mixdown/Escaped.wav"),
                    withDestinationURL: outside.appendingPathComponent("Escaped.wav")
                )
                try fm.createSymbolicLink(
                    at: folder.appendingPathComponent("Linked.cpr"),
                    withDestinationURL: outside
                )
            }
            folders.append(folder)
        }
        let loose = root.appendingPathComponent("Loose Idea.cpr")
        try placeholder.write(to: loose)
        try fm.setAttributes([.modificationDate: epoch], ofItemAtPath: loose.path)
        return SyntheticArchive(base: base, root: root, songFolders: folders)
    }

    private static let placeholder = Data("placeholder".utf8)

    /// A valid 16-bit mono 44.1 kHz WAV header with 8 bytes of silence.
    private static let wav: Data = {
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        append("RIFF"); append32(36 + 8); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1); append32(44_100); append32(88_200)
        append16(2); append16(16)
        append("data"); append32(8); data.append(contentsOf: [UInt8](repeating: 0, count: 8))
        return data
    }()
}

// MARK: - Counting file manager

final class CountingFileManager: FileManager, @unchecked Sendable {
    struct Counts {
        var enumerators = 0
        var enumeratedEntries = 0
        var contentsOfDirectory = 0
        var fileExists = 0
    }

    private let lock = NSLock()
    private var counts = Counts()

    func snapshot() -> Counts { lock.withLock { counts } }

    fileprivate func bump(_ update: (inout Counts) -> Void) { lock.withLock { update(&counts) } }

    override func __enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = [],
        errorHandler handler: ((URL, Error) -> Bool)? = nil
    ) -> FileManager.DirectoryEnumerator? {
        bump { $0.enumerators += 1 }
        guard let inner = super.__enumerator(
            at: url, includingPropertiesForKeys: keys, options: mask, errorHandler: handler
        ) else { return nil }
        return CountingEnumerator(inner: inner, owner: self)
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        bump { $0.contentsOfDirectory += 1 }
        return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }

    override func fileExists(atPath path: String) -> Bool {
        bump { $0.fileExists += 1 }
        return super.fileExists(atPath: path)
    }

    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        bump { $0.fileExists += 1 }
        return super.fileExists(atPath: path, isDirectory: isDirectory)
    }
}

private final class CountingEnumerator: FileManager.DirectoryEnumerator {
    private let inner: FileManager.DirectoryEnumerator
    private let owner: CountingFileManager

    init(inner: FileManager.DirectoryEnumerator, owner: CountingFileManager) {
        self.inner = inner
        self.owner = owner
        super.init()
    }

    override func nextObject() -> Any? {
        let next = inner.nextObject()
        if next != nil { owner.bump { $0.enumeratedEntries += 1 } }
        return next
    }

    override func skipDescendants() { inner.skipDescendants() }
    override var level: Int { inner.level }
    override var fileAttributes: [FileAttributeKey: Any]? { inner.fileAttributes }
    override var directoryAttributes: [FileAttributeKey: Any]? { inner.directoryAttributes }
    override var isEnumeratingDirectoryPostOrder: Bool { inner.isEnumeratingDirectoryPostOrder }
}
