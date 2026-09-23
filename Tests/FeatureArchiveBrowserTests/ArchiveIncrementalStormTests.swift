@testable import AppCore
import Foundation
@testable import FeatureArchiveBrowser
@testable import NikoMusicCore
import XCTest

/// End to end from watcher delivery to catalog merge for song folders that vanish or turn into
/// symlinks. The incremental result must match what a full scan of the same archive would show.
@MainActor
final class ArchiveIncrementalStormTests: XCTestCase {
    private var archive: SyntheticArchive!
    private var existing: [Song] = []

    override func setUp() async throws {
        archive = try SyntheticArchive.make(songCount: 4)
        existing = try MusicArchiveScanner().scan(roots: [archive.root]).songs
    }

    override func tearDown() async throws {
        archive?.remove()
    }

    func testDeletedSongFolderStormRemovesSong() async throws {
        let gone = archive.songFolders[1]
        let storm = (0..<1_100).map { "\(gone.path)/Audio/Take \($0).wav" } + ["\(gone.path)"]
        try FileManager.default.removeItem(at: gone)

        let merged = try await applyDelivered(storm)

        assertMatchesFullScan(merged)
        XCTAssertFalse(merged.contains { $0.id == gone.standardizedFileURL.path })
    }

    func testTrashedSongFolderSingleRenameEventRemovesSong() async throws {
        let gone = archive.songFolders[2]
        try FileManager.default.moveItem(at: gone, to: archive.base.appendingPathComponent("Trashed", isDirectory: true))

        let merged = try await applyDelivered([gone.path])

        assertMatchesFullScan(merged)
        XCTAssertFalse(merged.contains { $0.id == gone.standardizedFileURL.path })
    }

    func testDeletedSongFolderNestedEventsRemoveSong() async throws {
        let gone = archive.songFolders[0]
        let paths = (0..<20).map { "\(gone.path)/Mixdown/Bounce \($0).wav" }
        try FileManager.default.removeItem(at: gone)

        let merged = try await applyDelivered(paths)

        assertMatchesFullScan(merged)
    }

    func testSongFolderReplacedBySymlinkStormDoesNotCatalogTarget() async throws {
        let replaced = archive.songFolders[3]
        let target = archive.base.appendingPathComponent("Outside Song", isDirectory: true)
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Mixdown"), withIntermediateDirectories: true)
        try Data("placeholder".utf8).write(to: target.appendingPathComponent("Outside Song v9.cpr"))
        try Data("placeholder".utf8).write(to: target.appendingPathComponent("Mixdown/Outside Song v9.wav"))
        try FileManager.default.removeItem(at: replaced)
        try FileManager.default.createSymbolicLink(at: replaced, withDestinationURL: target)
        let storm = (0..<1_100).map { "\(replaced.path)/Mixdown/Take \($0).wav" }

        let merged = try await applyDelivered(storm)

        assertMatchesFullScan(merged)
        XCTAssertFalse(merged.flatMap(\.projectVersions).contains { $0.fileName == "Outside Song v9.cpr" })
    }

    func testIncrementalScanSkipsSymlinkedSongFolderLikeFullScan() throws {
        let linked = archive.root.appendingPathComponent("Linked Song", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: archive.songFolders[0])

        let full = try MusicArchiveScanner().scan(roots: [archive.root])
        let incremental = try MusicArchiveScanner().scanIncremental(
            resolution: ArchiveSongFolderResolver.resolve(changedPaths: [linked], roots: [archive.root]),
            roots: [archive.root]
        )

        XCTAssertTrue(incremental.songs.isEmpty)
        XCTAssertEqual(incremental.skippedEntries, full.skippedEntries.filter { $0.label == "Linked Song" })
        XCTAssertFalse(incremental.skippedEntries.isEmpty)
    }

    // MARK: - Helpers

    /// Feeds raw FSEvents paths through the real watcher (default 1,024-path budget), then
    /// through the coordinator's incremental update, as the app does.
    private func applyDelivered(_ rawPaths: [String]) async throws -> [Song] {
        let watcher = FSEventsArchiveRootWatcher(debounceInterval: 0.01)
        let delivered = DeliveredEvents()
        XCTAssertTrue(watcher.setRoots([archive.root]) { delivered.events.append($0) })
        defer { watcher.stop() }
        watcher.simulateFSEventBatch(paths: rawPaths, eventFlags: [])
        for _ in 0..<200 where delivered.events.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard case .paths(let changedPaths) = try XCTUnwrap(delivered.events.first) else {
            XCTFail("expected an incremental batch, got \(delivered.events)")
            return existing
        }
        let coordinator = ArchiveCatalogCoordinator(
            archiveIndexStore: nil, songMetadataStore: nil, collaboratorStore: nil,
            diagnostics: TestToolContext.make().diagnostics
        )
        let update = try await coordinator.applyIncrementalFilesystemUpdate(
            changedPaths: changedPaths, roots: [archive.root], existingSongs: existing,
            collaborators: [], priorDiagnostics: nil
        )
        return update?.songs ?? existing
    }

    private func assertMatchesFullScan(_ merged: [Song], file: StaticString = #filePath, line: UInt = #line) {
        let full = (try? MusicArchiveScanner().scan(roots: [archive.root]).songs) ?? []
        XCTAssertEqual(merged.map(\.id).sorted(), full.map(\.id).sorted(), file: file, line: line)
    }
}

@MainActor
private final class DeliveredEvents {
    var events: [ArchiveRootWatchEvent] = []
}
