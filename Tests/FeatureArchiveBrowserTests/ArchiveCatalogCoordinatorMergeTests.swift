import XCTest
@testable import FeatureArchiveBrowser
import NikoMusicCore

@MainActor
final class ArchiveCatalogCoordinatorMergeTests: XCTestCase {
    func testMergeIncrementalScanPreservesUnaffectedSiblingsWhenRootCPRChanges() {
        let root = URL(fileURLWithPath: "/Archive", isDirectory: true)
        let songAFolder = root.appendingPathComponent("Song A", isDirectory: true)
        let songBFolder = root.appendingPathComponent("Song B", isDirectory: true)
        let looseCPR = root.appendingPathComponent("Loose.cpr")

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
            affectedSongIDs: affected
        )

        XCTAssertEqual(Set(merged.map(\.displayTitle)), ["Song A", "Song B", "Loose Updated"])
    }

    func testMergeIncrementalScanRemovesDeletedSongFolder() {
        let root = URL(fileURLWithPath: "/Archive", isDirectory: true)
        let deletedFolder = root.appendingPathComponent("Removed", isDirectory: true)
        let remainingFolder = root.appendingPathComponent("Kept", isDirectory: true)

        let removed = makeFolderSong(folder: deletedFolder, title: "Removed")
        let kept = makeFolderSong(folder: remainingFolder, title: "Kept")

        let affected: Set<String> = [deletedFolder.standardizedFileURL.path]
        let incremental = ScanResult(songs: [])

        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: [removed, kept],
            incremental: incremental,
            affectedSongIDs: affected
        )

        XCTAssertEqual(merged.map(\.displayTitle), ["Kept"])
    }

    func testMergeIncrementalScanKeepsAffectedSongWhenFolderStillExistsButScanEmpty() {
        let root = URL(fileURLWithPath: "/Archive", isDirectory: true)
        let songFolder = root.appendingPathComponent("Song A", isDirectory: true)
        let song = makeFolderSong(folder: songFolder, title: "Song A")

        let affected: Set<String> = [songFolder.standardizedFileURL.path]
        let incremental = ScanResult(songs: [])

        let fileManager = FileManager()
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: songFolder, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
        }

        let merged = ArchiveCatalogCoordinator.mergeIncrementalScan(
            existing: [song],
            incremental: incremental,
            affectedSongIDs: affected,
            fileManager: fileManager
        )

        XCTAssertEqual(merged.map(\.displayTitle), ["Song A"])
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
