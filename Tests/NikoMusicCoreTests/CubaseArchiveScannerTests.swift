import XCTest
@testable import NikoMusicCore

final class CubaseArchiveScannerTests: XCTestCase {
    func testCancelledTaskStopsBeforeScanningRoots() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let task = Task.detached { () throws -> ScanResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return try CubaseArchiveScanner().scan(roots: [root])
        }

        do {
            _ = try await task.value
            XCTFail("Cancelled scans must stop before enumerating archive roots")
        } catch is CancellationError {
            // Expected: the scanner's cooperative cancellation check runs before I/O.
        }
    }

    func testScansOneSongPerImmediateChildFolder() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])

        let titles = Set(result.songs.map(\.displayTitle))
        XCTAssertTrue(titles.contains("Neon Hook"))
        XCTAssertTrue(titles.contains("Second Song"))
        XCTAssertTrue(titles.contains("Broken Folder Example"))
        XCTAssertTrue(titles.contains("Preview Ranking Lab"))
        XCTAssertTrue(titles.contains("90s Rave"))
        XCTAssertEqual(result.songs.count, 9)
    }

    func testBrokenFolderHasWarningAndNoCPR() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let broken = try XCTUnwrap(result.songs.first { $0.displayTitle == "Broken Folder Example" })
        XCTAssertTrue(broken.projectVersions.isEmpty)
        XCTAssertTrue(broken.scanWarnings.contains(where: { $0.contains("CPR") }))
    }

    func testBrokenFolderLoadsSidecarNotesText() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let broken = try XCTUnwrap(result.songs.first { $0.displayTitle == "Broken Folder Example" })
        XCTAssertEqual(broken.sidecarNotes, "notes only")
    }

    func testSongsWithoutSidecarNotesAreNil() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })
        XCTAssertNil(neon.sidecarNotes)
    }

    func testSkipsNonFolderEntriesAtRoot() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        XCTAssertTrue(
            result.skippedEntries.contains {
                $0.kind == .nonFolderAtRoot && $0.label == "LOOSE_FILE.txt"
            }
        )
    }

    func testSkipsSymbolicLinkFoldersAtArchiveRoot() throws {
        let root = try makeTemporaryRoot()
        let outside = try makeTemporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let outsideSong = outside.appendingPathComponent("External Song", isDirectory: true)
        let mixdown = outsideSong.appendingPathComponent("Mixdown", isDirectory: true)
        try FileManager.default.createDirectory(at: mixdown, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: mixdown.appendingPathComponent("escape.wav").path,
            contents: Data("fixture".utf8)
        )

        let alias = root.appendingPathComponent("Alias Song", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outsideSong)

        let realSong = root.appendingPathComponent("Real Song", isDirectory: true)
        try FileManager.default.createDirectory(at: realSong, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: realSong.appendingPathComponent("Real Song.cpr").path,
            contents: Data("fixture".utf8)
        )

        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [root])

        XCTAssertEqual(result.songs.map(\.displayTitle), ["Real Song"])
        XCTAssertTrue(
            result.skippedEntries.contains {
                $0.label == "Alias Song" && $0.reason.contains("symbolic-link")
            }
        )
    }

    func testScansRootLevelCPRFilesAsSongs() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("Loose Project.cpr")
        FileManager.default.createFile(atPath: project.path, contents: Data("fixture".utf8))
        let looseAudio = root.appendingPathComponent("loose.wav")
        FileManager.default.createFile(atPath: looseAudio.path, contents: Data("fixture".utf8))

        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [root])

        let song = try XCTUnwrap(result.songs.first { $0.displayTitle == "Loose Project" })
        XCTAssertEqual(song.projectVersions.map(\.fileName), ["Loose Project.cpr"])
        XCTAssertEqual(song.latestCPR?.filePath.standardizedFileURL, project.standardizedFileURL)
        XCTAssertFalse(result.skippedEntries.contains { $0.label == "Loose Project.cpr" })
        XCTAssertTrue(result.skippedEntries.contains { $0.label == "loose.wav" })
    }

    func testGroupsRootLevelCPRVersionsByProjectTitle() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("Loose Project v1.cpr").path,
            contents: Data("fixture".utf8)
        )
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("Loose Project v2.cpr").path,
            contents: Data("fixture".utf8)
        )

        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [root])

        let song = try XCTUnwrap(result.songs.first { $0.displayTitle == "Loose Project" })
        XCTAssertEqual(result.songs.count, 1)
        XCTAssertEqual(Set(song.projectVersions.map(\.fileName)), ["Loose Project v1.cpr", "Loose Project v2.cpr"])
    }

    func testNeonHookHasMultipleCPRFiles() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })
        XCTAssertGreaterThanOrEqual(neon.projectVersions.count, 1)
    }

    func testScanCombinesSongsFromMultipleRoots() throws {
        try CubaseFixtures.ensureGenerated()
        let buildDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
        let extraRoot = buildDir.appendingPathComponent("NikoMusicHubExtraArchiveRoot-\(UUID().uuidString)", isDirectory: true)
        let extraSongFolder = extraRoot.appendingPathComponent("Extra Archive Song", isDirectory: true)
        try FileManager.default.createDirectory(at: extraSongFolder, withIntermediateDirectories: true)
        let cpr = extraSongFolder.appendingPathComponent("Extra Archive Song.cpr")
        FileManager.default.createFile(atPath: cpr.path, contents: Data("fixture".utf8))
        defer { try? FileManager.default.removeItem(at: extraRoot) }

        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot, extraRoot])

        let titles = Set(result.songs.map(\.displayTitle))
        XCTAssertTrue(titles.contains("Neon Hook"))
        XCTAssertTrue(titles.contains("Extra Archive Song"))
        XCTAssertGreaterThan(result.songs.count, 9)
    }

    func testIncrementalScanUpdatesSingleSongFolder() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let songA = root.appendingPathComponent("Song A", isDirectory: true)
        let songB = root.appendingPathComponent("Song B", isDirectory: true)
        try FileManager.default.createDirectory(at: songA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: songB, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: songA.appendingPathComponent("Song A.cpr").path,
            contents: Data("fixture".utf8)
        )
        FileManager.default.createFile(
            atPath: songB.appendingPathComponent("Song B.cpr").path,
            contents: Data("fixture".utf8)
        )

        let scanner = CubaseArchiveScanner()
        let full = try scanner.scan(roots: [root])
        XCTAssertEqual(full.songs.count, 2)
        XCTAssertTrue(full.songs.allSatisfy { $0.previewCandidates.isEmpty })

        let mixdownFolder = songA.appendingPathComponent("mixdown", isDirectory: true)
        try FileManager.default.createDirectory(at: mixdownFolder, withIntermediateDirectories: true)
        let mixdown = mixdownFolder.appendingPathComponent("Song A mix.wav")
        FileManager.default.createFile(atPath: mixdown.path, contents: Data("fixture".utf8))

        let resolution = ArchiveSongFolderResolver.resolve(changedPaths: [mixdown], roots: [root])
        let incremental = try scanner.scanIncremental(resolution: resolution, roots: [root])

        XCTAssertEqual(incremental.songs.count, 1)
        let updated = try XCTUnwrap(incremental.songs.first)
        XCTAssertEqual(updated.displayTitle, "Song A")
        XCTAssertEqual(updated.previewCandidates.count, 1)
        XCTAssertEqual(updated.previewCandidates.first?.fileName, "Song A mix.wav")
    }

    func testAutoPreviewPrefersFullDemoOverCoverVocalExport() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let songFolder = root.appendingPathComponent("S2 Seoul", isDirectory: true)
        let mixdown = songFolder.appendingPathComponent("Mixdown", isDirectory: true)
        try FileManager.default.createDirectory(at: mixdown, withIntermediateDirectories: true)
        let demoName = "drinking kinda situation demo v1 (day one 4).wav"
        let vocalsName = "drinking kinda situation demo v1 (day one 4) (Cover) (Vocals).wav"
        FileManager.default.createFile(
            atPath: mixdown.appendingPathComponent(demoName).path,
            contents: Data("fixture".utf8)
        )
        FileManager.default.createFile(
            atPath: mixdown.appendingPathComponent(vocalsName).path,
            contents: Data("fixture".utf8)
        )

        let result = try CubaseArchiveScanner().scan(roots: [root])
        let song = try XCTUnwrap(result.songs.first { $0.originalFolderName == "S2 Seoul" })
        let main = try XCTUnwrap(song.previewCandidates.first)
        let vocals = try XCTUnwrap(song.previewCandidates.first { $0.fileName == vocalsName })

        XCTAssertEqual(main.fileName, demoName)
        XCTAssertEqual(song.mainPreviewCandidateID, main.id)
        XCTAssertEqual(vocals.detectedRole, .acapella)
        XCTAssertTrue(vocals.confidenceReasons.contains("filename:negative-cover"))
        XCTAssertTrue(vocals.confidenceReasons.contains("filename:negative-vocals"))
    }

    func testUnreadableImmediateChildIsSkippedWhileSiblingsScan() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let goodSong = root.appendingPathComponent("Good Song", isDirectory: true)
        try FileManager.default.createDirectory(at: goodSong, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: goodSong.appendingPathComponent("Good Song.cpr").path,
            contents: Data("fixture".utf8)
        )
        let unreadable = root.appendingPathComponent("Unreadable Song", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unreadable.path) }

        let result = try CubaseArchiveScanner().scan(roots: [root])

        XCTAssertEqual(result.songs.map(\.displayTitle), ["Good Song"])
        let skipped = try XCTUnwrap(result.skippedEntries.first { $0.label == "Unreadable Song" })
        XCTAssertEqual(skipped.kind, .unreadableChild)
        XCTAssertTrue(skipped.reason.contains("Could not scan folder"))
        let matches = SkippedEntrySearchMatcher.search("Unreadable", in: result.skippedEntries)
        XCTAssertEqual(matches.first?.entry.label, "Unreadable Song")
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubScanner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
