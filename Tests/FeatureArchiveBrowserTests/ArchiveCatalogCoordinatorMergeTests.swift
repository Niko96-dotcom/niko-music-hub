import XCTest
@testable import FeatureArchiveBrowser
import NikoMusicCore

@MainActor
final class ArchiveCatalogCoordinatorMergeTests: XCTestCase {
    func testMergeIncrementalScanPreservesUnaffectedSiblingsWhenRootCPRChanges() throws {
        let root = try makeMergeTestRoot()
        let songAFolder = root.appendingPathComponent("Song A", isDirectory: true)
        let songBFolder = root.appendingPathComponent("Song B", isDirectory: true)
        let looseCPR = root.appendingPathComponent("Loose.cpr")

        let fileManager = FileManager()
        try fileManager.createDirectory(at: songAFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: songBFolder, withIntermediateDirectories: true)
        fileManager.createFile(atPath: looseCPR.path, contents: Data("fixture".utf8))
        defer { try? fileManager.removeItem(at: root) }

        let songA = makeFolderSong(folder: songAFolder, title: "Song A")
        let songB = makeFolderSong(folder: songBFolder, title: "Song B")
        let looseSong = makeRootCPRSong(cprPath: looseCPR, title: "Loose")

        let affected: Set<String> = [looseCPR.standardizedFileURL.path]
        let updatedLoose = Song(
            folderPath: looseCPR,
            originalFolderName: "Loose.cpr",
            displayTitle: "Loose Updated",
            projectVersions: looseSong.projectVersions
        )
        let incremental = ScanResult(songs: [updatedLoose])

        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: [songA, songB, looseSong],
            incremental: incremental,
            affectedSongIDs: affected,
            fileManager: fileManager
        )

        XCTAssertEqual(Set(merged.map(\.displayTitle)), ["Song A", "Song B", "Loose Updated"])
    }

    func testMergeIncrementalScanRemovesDeletedSongFolder() throws {
        let root = try makeMergeTestRoot()
        let deletedFolder = root.appendingPathComponent("Removed", isDirectory: true)
        let remainingFolder = root.appendingPathComponent("Kept", isDirectory: true)

        let fileManager = FileManager()
        try fileManager.createDirectory(at: remainingFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let removed = makeFolderSong(folder: deletedFolder, title: "Removed")
        let kept = makeFolderSong(folder: remainingFolder, title: "Kept")

        let affected: Set<String> = [deletedFolder.standardizedFileURL.path]
        let incremental = ScanResult(songs: [])

        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: [removed, kept],
            incremental: incremental,
            affectedSongIDs: affected,
            fileManager: fileManager
        )

        XCTAssertEqual(merged.map(\.displayTitle), ["Kept"])
    }

    func testMergeIncrementalScanDropsGhostAfterFolderRename() throws {
        let root = try makeMergeTestRoot()
        let oldFolder = root.appendingPathComponent("Old Name", isDirectory: true)
        let newFolder = root.appendingPathComponent("New Name", isDirectory: true)
        let siblingFolder = root.appendingPathComponent("Sibling", isDirectory: true)

        let fileManager = FileManager()
        try fileManager.createDirectory(at: newFolder, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: siblingFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let oldSong = makeFolderSong(folder: oldFolder, title: "Old Name")
        let sibling = makeFolderSong(folder: siblingFolder, title: "Sibling")
        let renamed = makeFolderSong(folder: newFolder, title: "New Name")

        // Finder-style rename: only the new path is reported as affected.
        let affected: Set<String> = [newFolder.standardizedFileURL.path]
        let incremental = ScanResult(songs: [renamed])

        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: [oldSong, sibling],
            incremental: incremental,
            affectedSongIDs: affected,
            fileManager: fileManager
        )

        XCTAssertEqual(Set(merged.map(\.displayTitle)), ["New Name", "Sibling"])
        XCTAssertFalse(merged.contains(where: { $0.id == oldSong.id }))
    }

    func testMergeIncrementalScanKeepsAffectedSongWhenFolderStillExistsButScanEmpty() throws {
        let root = try makeMergeTestRoot()
        let songFolder = root.appendingPathComponent("Song A", isDirectory: true)
        let song = makeFolderSong(folder: songFolder, title: "Song A")

        let affected: Set<String> = [songFolder.standardizedFileURL.path]
        let incremental = ScanResult(songs: [])

        let fileManager = FileManager()
        try fileManager.createDirectory(at: songFolder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: [song],
            incremental: incremental,
            affectedSongIDs: affected,
            fileManager: fileManager
        )

        XCTAssertEqual(merged.map(\.displayTitle), ["Song A"])
    }

    private func makeMergeTestRoot() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("NikoMusicHubMerge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeFolderSong(folder: URL, title: String) -> Song {
        Song(
            folderPath: folder,
            originalFolderName: folder.lastPathComponent,
            displayTitle: title
        )
    }

    private func makeRootCPRSong(cprPath: URL, title: String) -> Song {
        Song(
            folderPath: cprPath,
            originalFolderName: cprPath.lastPathComponent,
            displayTitle: title,
            projectVersions: [
                ProjectVersion(
                    filePath: cprPath,
                    fileName: cprPath.lastPathComponent,
                    modifiedAt: Date()
                )
            ]
        )
    }
}
