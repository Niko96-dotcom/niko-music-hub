import XCTest
@testable import NikoMusicCore

final class ArchiveSongFolderResolverTests: XCTestCase {
    func testResolvesNestedMixdownToSongFolder() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let songFolder = root.appendingPathComponent("Neon Hook", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        let mixdown = songFolder
            .appendingPathComponent("mixdown", isDirectory: true)
            .appendingPathComponent("Neon Hook.wav")

        let resolution = ArchiveSongFolderResolver.resolve(
            changedPaths: [mixdown],
            roots: [root]
        )

        XCTAssertEqual(resolution.songFolders, [songFolder.standardizedFileURL])
        XCTAssertTrue(resolution.rootsForRootLevelScan.isEmpty)
    }

    func testResolvesRootDirectoryToRootRescanOnly() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let songFolder = root.appendingPathComponent("Neon Hook", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)

        let resolution = ArchiveSongFolderResolver.resolve(
            changedPaths: [root],
            roots: [root]
        )

        // Root-level noise must not fan out into every child song folder.
        XCTAssertTrue(resolution.songFolders.isEmpty)
        XCTAssertEqual(resolution.rootsForRootLevelScan, [root.standardizedFileURL])
    }

    func testResolvesRootLevelCPRToRootRescan() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cpr = root.appendingPathComponent("Loose Project.cpr")

        let resolution = ArchiveSongFolderResolver.resolve(
            changedPaths: [cpr],
            roots: [root]
        )

        XCTAssertTrue(resolution.songFolders.isEmpty)
        XCTAssertEqual(resolution.rootsForRootLevelScan, [root.standardizedFileURL])
    }

    func testResolvesNestedRootsToDeepestMatch() throws {
        let outer = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: outer) }
        let inner = outer.appendingPathComponent("Inner Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let songFolder = inner.appendingPathComponent("Nested Song", isDirectory: true)
        try FileManager.default.createDirectory(at: songFolder, withIntermediateDirectories: true)
        let mixdown = songFolder
            .appendingPathComponent("mixdown", isDirectory: true)
            .appendingPathComponent("Nested Song.wav")

        let resolution = ArchiveSongFolderResolver.resolve(
            changedPaths: [mixdown],
            roots: [outer, inner]
        )

        XCTAssertEqual(resolution.songFolders, [songFolder.standardizedFileURL])
    }

    func testIgnoresPathsOutsideRoots() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("outside-\(UUID().uuidString).wav")

        let resolution = ArchiveSongFolderResolver.resolve(
            changedPaths: [outside],
            roots: [root]
        )

        XCTAssertTrue(resolution.isEmpty)
    }

    func testIgnoresHiddenRootChildrenLikeVaultStaging() throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stagingFile = root
            .appendingPathComponent(".niko-staging", isDirectory: true)
            .appendingPathComponent("project", isDirectory: true)
            .appendingPathComponent("restore.cpr")
        try FileManager.default.createDirectory(
            at: stagingFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let resolution = ArchiveSongFolderResolver.resolve(
            changedPaths: [stagingFile],
            roots: [root]
        )

        XCTAssertTrue(resolution.isEmpty)
    }

    func testOnlyBatchesTouchingRootEntriesMayMoveSongFolders() {
        let root = URL(fileURLWithPath: "/Volumes/Fixture Archive", isDirectory: true)
        func mayMove(_ paths: [String]) -> Bool {
            ArchiveSongFolderResolver.mayMoveSongFolders(
                changedPaths: paths.map { URL(fileURLWithPath: $0) },
                roots: [root]
            )
        }

        XCTAssertFalse(mayMove(["/Volumes/Fixture Archive/Song/Song v3.cpr", "/Volumes/Fixture Archive/Song/Mixdown/a.wav"]))
        XCTAssertFalse(mayMove(["/Volumes/Fixture Archive/.DS_Store", "/Volumes/Fixture Archive/.niko-staging/Song/x.cpr"]))
        XCTAssertTrue(mayMove(["/Volumes/Fixture Archive/Song/Song v3.cpr", "/Volumes/Fixture Archive/Renamed Song"]))
        XCTAssertTrue(mayMove(["/Volumes/Fixture Archive/Loose.cpr"]))
        XCTAssertTrue(mayMove(["/Volumes/Fixture Archive"]))
        XCTAssertTrue(mayMove(["/Volumes/Other/Song/x.cpr"]))
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("NikoMusicHubResolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
