import Darwin
import Foundation
@testable import NikoMusicCore
import XCTest

/// Symlink attacks against a full scan. Every archive is built under a fresh temporary directory;
/// no real music is read.
extension ArchiveScanEquivalenceTests {
    func testSymlinkAttackArchiveMatchesStandaloneDetectors() throws {
        let archive = try SymlinkAttackArchive.make()
        defer { archive.remove() }
        try assertScanMatchesStandaloneDetectors(root: archive.root)
    }

    /// The whole scan result — songs, previews, projects, notes, warnings and skipped entries —
    /// as the scanner produced it before per-entry resolution moved into the enumeration.
    func testSymlinkAttackArchiveScanIsUnchanged() throws {
        let archive = try SymlinkAttackArchive.make()
        defer { archive.remove() }
        let result = try MusicArchiveScanner().scan(roots: [archive.root])
        XCTAssertEqual(archive.describe(result), SymlinkAttackArchive.expectedScan)
    }

    func testSymlinkAttackArchiveIncrementalScanIsUnchanged() throws {
        let archive = try SymlinkAttackArchive.make()
        defer { archive.remove() }
        let full = try MusicArchiveScanner().scan(roots: [archive.root])
        let folders = ["Song A", "Song B", "Song C", "Linked Song", "Root Loop"].map {
            archive.root.appendingPathComponent($0, isDirectory: true)
        }
        let incremental = try MusicArchiveScanner().scanIncremental(
            resolution: ArchiveSongFolderResolver.Resolution(songFolders: Set(folders)),
            roots: [archive.root]
        )
        let folderIDs = Set(folders.map(\.standardizedFileURL.path))
        let fullFolderSongs = full.songs.filter { folderIDs.contains($0.id) }
        XCTAssertEqual(fullFolderSongs.count, 3)
        assertSameCatalog(incremental.songs, fullFolderSongs)
        XCTAssertEqual(
            incremental.skippedEntries.map { "\($0.kind.rawValue)|\($0.label)|\($0.reason)" },
            [
                "unreadableChild|Linked Song|Skipped symbolic-link folder at archive root",
                "unreadableChild|Root Loop|Skipped symbolic-link folder at archive root"
            ]
        )
    }

    /// An incremental rescan whose song folder is swapped for an outside link mid-walk. Uses
    /// only the pre-existing `entryListed` hook and the attack fixture, so it compiles on the
    /// original HEAD and fails there (the `resourceValues`/`fileExists` check already passed, so
    /// the walk re-opens paths through the swapped link); the fix `lstat`-verifies the song base
    /// (`O_NOFOLLOW` plus `dev`/`ino`) and discards it with the existing symlink reason.
    func testIncrementalSongFolderSwappedToOutsideLinkIsNotScanned() throws {
        let archive = try SymlinkAttackArchive.make()
        defer { archive.remove() }
        let songA = archive.root.appendingPathComponent("Song A", isDirectory: true)
        let innerSongA = songA.resolvingSymlinksInPath().path + "/"
        let outsideDir = archive.base.appendingPathComponent("Outside/Dir", isDirectory: true)
        var scanner = MusicArchiveScanner()
        var swapped = false
        scanner.raceHooks.entryListed = { _ in
            guard !swapped else { return }
            swapped = true
            do {
                try FileManager.default.moveItem(
                    at: songA, to: archive.base.appendingPathComponent("Parked Song A")
                )
                try FileManager.default.createSymbolicLink(at: songA, withDestinationURL: outsideDir)
            } catch {
                XCTFail("Could not swap song folder: \(error)")
            }
        }
        let incremental = try scanner.scanIncremental(
            resolution: ArchiveSongFolderResolver.Resolution(songFolders: Set([songA])),
            roots: [archive.root]
        )
        XCTAssertTrue(swapped)
        XCTAssertEqual(
            incremental.skippedEntries.map { "\($0.kind.rawValue)|\($0.label)|\($0.reason)" },
            ["unreadableChild|Song A|Skipped symbolic-link folder at archive root"]
        )
        XCTAssertTrue(incremental.songs.isEmpty, "swapped base must not return dangling inside paths")
        for song in incremental.songs {
            for path in song.previewCandidates.map(\.filePath) + song.projectVersions.map(\.filePath) {
                XCTAssertTrue(path.resolvingSymlinksInPath().path.hasPrefix(innerSongA), path.path)
            }
        }
    }

    /// A song folder that already is a symlink to outside before `scanIncremental` starts.
    /// The candidate URL is listed via `contentsOfDirectory` (with the link key prefetched)
    /// while the folder is still real, then the real folder is moved aside and the outside
    /// link installed — so on the original HEAD the prefetched `resourceValues` still report
    /// "not a link" and `fileExists` follows it, and the walk returns an outside song with no
    /// skipped entry. The fix `lstat`-verifies the base and reports the existing symlink reason.
    func testIncrementalSongFolderAlreadyALinkIsSkipped() throws {
        let archive = try SymlinkAttackArchive.make()
        defer { archive.remove() }
        let listed = try FileManager.default.contentsOfDirectory(
            at: archive.root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let prefetchedSongA = try XCTUnwrap(listed.first { $0.lastPathComponent == "Song A" })
        XCTAssertEqual(
            try prefetchedSongA.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink,
            false
        )
        let songAPath = archive.root.appendingPathComponent("Song A", isDirectory: true)
        let outsideDir = archive.base.appendingPathComponent("Outside/Dir", isDirectory: true)
        try FileManager.default.moveItem(
            at: songAPath, to: archive.base.appendingPathComponent("Parked Song A")
        )
        try FileManager.default.createSymbolicLink(at: songAPath, withDestinationURL: outsideDir)
        let incremental = try MusicArchiveScanner().scanIncremental(
            resolution: ArchiveSongFolderResolver.Resolution(songFolders: Set([prefetchedSongA])),
            roots: [archive.root]
        )
        XCTAssertEqual(
            incremental.skippedEntries.map { "\($0.kind.rawValue)|\($0.label)|\($0.reason)" },
            ["unreadableChild|Song A|Skipped symbolic-link folder at archive root"]
        )
        XCTAssertTrue(incremental.songs.isEmpty, "linked base must not return an outside song")
    }

    /// Nothing a scan returns may resolve outside its song folder.
    func testSymlinkAttackArchiveNeverLeavesASong() throws {
        let archive = try SymlinkAttackArchive.make()
        defer { archive.remove() }
        let result = try MusicArchiveScanner().scan(roots: [archive.root])
        for song in result.songs where song.latestCPR?.filePath != song.folderPath {
            let folder = song.folderPath.resolvingSymlinksInPath().path + "/"
            for path in song.previewCandidates.map(\.filePath) + song.projectVersions.map(\.filePath) {
                XCTAssertTrue(path.resolvingSymlinksInPath().path.hasPrefix(folder), path.path)
            }
        }
    }
}

/// Per-entry proof for `EnumeratedPathResolver`: for every entry of every song folder, its answer
/// equals the full `PathSafety` resolution the scan used to run on each file.
final class EnumeratedPathResolverOracleTests: XCTestCase {
    func testAttackArchiveEntriesMatchFullResolution() throws {
        let archive = try SymlinkAttackArchive.make()
        defer { archive.remove() }
        let (derived, checked) = try assertEveryEntryMatchesFullResolution(under: archive.root)
        XCTAssertGreaterThan(derived, 0)
        XCTAssertGreaterThan(checked, derived, "links must take the full check")
    }

    func testSyntheticArchiveEntriesMatchFullResolution() throws {
        let archive = try SyntheticArchive.make(songCount: 40)
        defer { archive.remove() }
        try assertEveryEntryMatchesFullResolution(under: archive.root)
    }

    func testFixtureArchiveEntriesMatchFullResolution() throws {
        try CubaseFixtures.ensureGenerated()
        try assertEveryEntryMatchesFullResolution(under: CubaseFixtures.archiveRoot)
    }

    /// A root below a symbolic link, with the wrong letter case, or spelled `/private/var/...`
    /// makes the enumerator name entries under a different base than the folder it was given.
    func testRootSpellingsThatDifferFromTheEnumerationBase() throws {
        let archive = try SymlinkAttackArchive.make()
        defer { archive.remove() }
        let aliasBase = archive.base.appendingPathComponent("Alias Base", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: aliasBase, withDestinationURL: archive.base)
        let spellings = [
            aliasBase.appendingPathComponent("Archive", isDirectory: true),
            URL(fileURLWithPath: archive.root.path.replacingOccurrences(of: "/Archive", with: "/ARCHIVE"), isDirectory: true),
            URL(fileURLWithPath: "/private" + archive.root.path, isDirectory: true)
        ]
        for root in spellings {
            try assertEveryEntryMatchesFullResolution(under: root)
            let expected = try MusicArchiveScanner().scan(roots: [archive.root])
            let actual = try MusicArchiveScanner().scan(roots: [root])
            XCTAssertEqual(
                actual.songs.map { $0.previewCandidates.map(\.fileName) },
                expected.songs.map { $0.previewCandidates.map(\.fileName) },
                root.path
            )
            XCTAssertEqual(
                actual.songs.map { $0.projectVersions.map(\.fileName) },
                expected.songs.map { $0.projectVersions.map(\.fileName) },
                root.path
            )
            try assertScanMatchesReference(root: root)
        }
    }

    /// The enumeration the resolver relies on lists links without descending into them, so no
    /// entry has a link among its ancestors below the folder.
    func testEnumerationNeverDescendsIntoSymbolicLinks() throws {
        let archive = try SymlinkAttackArchive.make()
        defer { archive.remove() }
        var sawLink = false
        for folder in try songFolders(under: archive.root) + [archive.base.appendingPathComponent("Outside/SongOutside")] {
            let enumerator = try XCTUnwrap(FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: EnumeratedPathResolver.prefetchedKeys,
                options: [.skipsHiddenFiles]
            ))
            for case let url as URL in enumerator {
                let components = url.pathComponents
                for depth in 1..<enumerator.level {
                    let ancestor = NSString.path(withComponents: Array(components.dropLast(depth)))
                    XCTAssertFalse(Self.isSymbolicLink(ancestor), "\(url.path) is below link \(ancestor)")
                }
                sawLink = sawLink || Self.isSymbolicLink(url.path)
            }
        }
        XCTAssertTrue(sawLink)
        // A song folder that is itself a link yields nothing to enumerate.
        let linkedSong = archive.root.appendingPathComponent("Linked Song")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: linkedSong, includingPropertiesForKeys: EnumeratedPathResolver.prefetchedKeys, options: [.skipsHiddenFiles]
        ))
        XCTAssertNil(enumerator.nextObject())
    }

    @discardableResult
    private func assertEveryEntryMatchesFullResolution(
        under root: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (derived: Int, checked: Int) {
        let safety = PathSafety()
        var derived = 0
        var checked = 0
        for folder in try songFolders(under: root) {
            let resolver = EnumeratedPathResolver(folder: folder, fileManager: .default)
            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: EnumeratedPathResolver.prefetchedKeys,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                let resolution = resolver.resolve(resolver.observe(url, level: enumerator.level))
                checked += 1
                XCTAssertEqual(
                    resolution.isContained, safety.isResolvedContained(url, in: [folder]), url.path, file: file, line: line
                )
                guard let canonical = resolution.canonicalPath else { continue }
                derived += 1
                XCTAssertEqual(canonical, safety.resolvedPath(of: url), url.path, file: file, line: line)
                XCTAssertEqual(canonical, url.resolvingSymlinksInPath().standardizedFileURL.path, url.path, file: file, line: line)
            }
        }
        XCTAssertGreaterThan(checked, 0, file: file, line: line)
        return (derived, checked)
    }

    private func assertScanMatchesReference(root: URL) throws {
        for song in try MusicArchiveScanner().scan(roots: [root]).songs {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: song.folderPath.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            XCTAssertEqual(song, try ArchiveScanEquivalenceTests.referenceSong(folder: song.folderPath), song.id)
        }
    }

    private func songFolders(under root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    private static func isSymbolicLink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }
}

// MARK: - Symlink attack archive

/// An archive whose songs try to reach outside themselves through symbolic links.
struct SymlinkAttackArchive {
    let base: URL
    let root: URL

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }

    static func make() throws -> SymlinkAttackArchive {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("nmh-symlink-attack-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Archive", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        var offset = 0.0
        func write(_ relative: String, in folder: URL, _ data: Data = wav) throws {
            let url = folder.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            offset += 60
            try fm.setAttributes([.modificationDate: epoch.addingTimeInterval(offset)], ofItemAtPath: url.path)
        }
        func link(_ relative: String, in folder: URL, to destination: String) throws {
            let url = folder.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
        }
        let placeholder = Data("placeholder".utf8)

        try write("secret.wav", in: outside)
        try write("secret notes.txt", in: outside, Data("outside secret".utf8))
        try write("Other v9.cpr", in: outside, placeholder)
        try write("Dir/stolen.wav", in: outside)
        try write("Dir/Stolen v8.cpr", in: outside, placeholder)
        try write("SongOutside/Outside Song v1.cpr", in: outside, placeholder)
        try write("SongOutside/Mixdown/Outside Song mix.wav", in: outside)

        let songA = root.appendingPathComponent("Song A", isDirectory: true)
        try write("Song A v1.cpr", in: songA, placeholder)
        try write("Mixdown/Song A mix.wav", in: songA)
        try write("Mixdown/Café Master.wav", in: songA)
        try link("Mixdown/Escape.wav", in: songA, to: outside.appendingPathComponent("secret.wav").path)
        try link("Mixdown/Relative Escape.wav", in: songA, to: "../../../Outside/secret.wav")
        try link("Mixdown/Alias.wav", in: songA, to: "Song A mix.wav")
        try link("Escape v9.cpr", in: songA, to: outside.appendingPathComponent("Other v9.cpr").path)
        try link("Alias v2.cpr", in: songA, to: "Song A v1.cpr")
        try link("Linked Dir", in: songA, to: outside.appendingPathComponent("Dir").path)
        try link("Linked Project.cpr", in: songA, to: outside.appendingPathComponent("Dir").path)
        try link("Inner Link", in: songA, to: "Mixdown")
        try link("Loop A.wav", in: songA, to: "Loop B.wav")
        try link("Loop B.wav", in: songA, to: "Loop A.wav")
        try link("Loop.cpr", in: songA, to: "Loop.cpr")
        try link("Loop Dir", in: songA, to: "Loop Dir")
        try link("Dangling.wav", in: songA, to: "missing.wav")
        try link("notes.txt", in: songA, to: outside.appendingPathComponent("secret notes.txt").path)

        let songB = root.appendingPathComponent("Song B", isDirectory: true)
        try write("Song B v3.cpr", in: songB, placeholder)
        try write("Stems/Drums.wav", in: songB)
        try write("Real Notes.txt", in: songB, Data("inside".utf8))
        try link("Sibling", in: songB, to: songA.appendingPathComponent("Mixdown").path)
        try link("Sibling Mix.wav", in: songB, to: "../Song A/Mixdown/Song A mix.wav")
        try link("Sibling v1.cpr", in: songB, to: "../Song A/Song A v1.cpr")
        try link("notes.txt", in: songB, to: "Real Notes.txt")

        let songC = root.appendingPathComponent("Song C", isDirectory: true)
        try write("Deep/Er/Song C v4.cpr", in: songC, placeholder)
        try write("Deep/Er/Mixdown/Song C final.wav", in: songC)
        try write("notes.txt", in: songC, Data("  real note  ".utf8))
        try link("Deep/Er/Up", in: songC, to: "../..")
        try link("Deep/Er/Out.wav", in: songC, to: "../../../../Outside/secret.wav")

        try link("Linked Song", in: root, to: outside.appendingPathComponent("SongOutside").path)
        try link("Root Loop", in: root, to: "Root Loop")
        try link("Linked Loose.cpr", in: root, to: outside.appendingPathComponent("Other v9.cpr").path)
        try write("Loose Idea.cpr", in: root, placeholder)
        return SymlinkAttackArchive(base: base, root: root)
    }

    /// A stable, root-relative rendering of a scan result.
    func describe(_ result: ScanResult) -> String {
        let prefixes = [root.path, root.resolvingSymlinksInPath().path, "/private" + root.path]
        func relative(_ url: URL) -> String {
            var path = url.standardizedFileURL.path
            for prefix in prefixes where path.hasPrefix(prefix + "/") {
                path = String(path.dropFirst(prefix.count + 1))
                break
            }
            return path
        }
        var lines: [String] = []
        for song in result.songs {
            lines.append("song \(relative(song.folderPath)) title=\(song.displayTitle)")
            for version in song.projectVersions {
                lines.append("  project \(relative(version.filePath)) v=\(version.detectedVersionNumber.map(String.init) ?? "-")")
            }
            if let latest = song.latestCPR { lines.append("  latest \(relative(latest.filePath))") }
            for preview in song.previewCandidates {
                let duration = preview.durationSeconds.map { String(format: "%.4f", $0) } ?? "-"
                lines.append(
                    "  preview \(relative(preview.filePath)) role=\(preview.folderRole) detected=\(preview.detectedRole) "
                        + "score=\(preview.confidenceScore) duration=\(duration)"
                )
            }
            if let main = song.mainPreviewCandidateID,
               let preview = song.previewCandidates.first(where: { $0.id == main }) {
                lines.append("  main \(relative(preview.filePath))")
            }
            for warning in song.scanWarnings { lines.append("  warning \(warning)") }
            if let notes = song.sidecarNotes { lines.append("  notes \(notes)") }
        }
        for warning in result.globalWarnings { lines.append("global \(warning)") }
        for entry in result.skippedEntries { lines.append("skipped \(entry.kind.rawValue)|\(entry.label)|\(entry.reason)") }
        return lines.joined(separator: "\n")
    }

    /// Recorded from the scanner before `EnumeratedPathResolver` existed.
    static let expectedScan = """
    song Loose Idea.cpr title=Loose Idea
      project Loose Idea.cpr v=-
      latest Loose Idea.cpr
    song Song A title=Song A
      project Song A/Song A v1.cpr v=1
      latest Song A/Song A v1.cpr
      preview Song A/Mixdown/Song A mix.wav role=mixdown detected=mainMix score=9.0 duration=0.0001
      preview Song A/Mixdown/Café Master.wav role=mixdown detected=master score=5.0 duration=0.0001
      main Song A/Mixdown/Song A mix.wav
    song Song B title=Song B
      project Song B/Song B v3.cpr v=3
      latest Song B/Song B v3.cpr
      preview Song B/Stems/Drums.wav role=stems detected=stems score=-179.0 duration=0.0001
      main Song B/Stems/Drums.wav
    song Song C title=Song C
      project Song C/Deep/Er/Song C v4.cpr v=4
      latest Song C/Deep/Er/Song C v4.cpr
      preview Song C/Deep/Er/Mixdown/Song C final.wav role=mixdown detected=unknown score=-85.0 duration=0.0001
      main Song C/Deep/Er/Mixdown/Song C final.wav
      notes real note
    skipped unreadableChild|Linked Loose.cpr|Skipped symbolic-link folder at archive root
    skipped unreadableChild|Linked Song|Skipped symbolic-link folder at archive root
    skipped unreadableChild|Root Loop|Skipped symbolic-link folder at archive root
    """

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
