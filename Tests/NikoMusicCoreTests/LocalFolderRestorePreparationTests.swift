import Foundation
import XCTest
@testable import NikoMusicCore

final class LocalFolderRestorePreparationTests: XCTestCase {
    func testKnownManifestDownloadsOnlyItsExpectedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let project = root.appendingPathComponent("Song.cpr")
        try Data("project".utf8).write(to: project)
        let manifest = try VaultManifestBuilder().build(at: root)
        try Data().write(to: project)
        try Data().write(to: root.appendingPathComponent("Unexpected.wav"))
        let provider = LocalFolderArchiveStorage(root: root, fileManager: .default, flushSeam: .live,
            readPlaceholder: { url in
                XCTAssertEqual(url.lastPathComponent, "Song.cpr")
                try Data("project".utf8).write(to: url)
            })
        try await provider.materialize(root, manifest: manifest)
        XCTAssertEqual(try Data(contentsOf: project), Data("project".utf8))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Unexpected.wav")).count, 0)
    }

    func testRestorePreparationReadsEmptyPlaceholdersBeforeVerifyingKnownManifest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let project = root.appendingPathComponent("Song.cpr")
        let data = Data("downloaded project".utf8)
        try data.write(to: project)
        let manifest = try VaultManifestBuilder().build(at: root)
        try Data().write(to: project)
        let provider = LocalFolderArchiveStorage(root: root, fileManager: .default, flushSeam: .live,
            readPlaceholder: { url in
                XCTAssertEqual(url.resolvingSymlinksInPath(), project.resolvingSymlinksInPath())
                try data.write(to: url)
            })
        // Metadata-only status must not read or silently hydrate anything.
        _ = try await provider.currentLocality(at: root, manifest: manifest)
        XCTAssertEqual(try Data(contentsOf: project).count, 0)
        try await provider.materialize(root, manifest: manifest)
        try VaultManifestBuilder().verify(manifest, at: root)
    }

    func testFailedPlaceholderReadCanBeRetriedWithoutDiscardingItsBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let project = root.appendingPathComponent("Song.cpr")
        try Data().write(to: project)
        let failed = LocalFolderArchiveStorage(root: root, fileManager: .default, flushSeam: .live,
            readPlaceholder: { _ in throw LocalFolderStorageError.unreadable })
        do {
            try await failed.prepareForRestoreInventory(root)
            XCTFail("Failed downloads must propagate")
        } catch { XCTAssertEqual(error as? LocalFolderStorageError, .unreadable) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.path))
        // A genuine empty file remains valid after a real coordinated read.
        try await LocalFolderArchiveStorage(root: root).prepareForRestoreInventory(root)
        XCTAssertEqual(try Data(contentsOf: project).count, 0)
    }

    func testRestorePreparationRejectsSymlinkBeforeAnyPlaceholderRead() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Escape"),
            withDestinationURL: FileManager.default.temporaryDirectory)
        let provider = LocalFolderArchiveStorage(root: root, fileManager: .default, flushSeam: .live,
            readPlaceholder: { _ in XCTFail("No read may escape the selected project") })
        do {
            try await provider.prepareForRestoreInventory(root)
            XCTFail("Symlink must be rejected")
        } catch { XCTAssertEqual(error as? FileProviderArchiveStorageError, .locationOutsideRoot) }
    }
}
