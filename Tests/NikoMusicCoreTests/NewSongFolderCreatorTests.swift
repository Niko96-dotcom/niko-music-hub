import XCTest
@testable import NikoMusicCore

final class NewSongFolderCreatorTests: XCTestCase {
    func testCreateRejectsSymlinkedOutputInsideArchiveRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("new-song-symlink-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        let linkedDraftRoot = outside.appendingPathComponent("New Song Drafts", isDirectory: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createSymbolicLink(at: linkedDraftRoot, withDestinationURL: archive)

        XCTAssertThrowsError(
            try NewSongFolderCreator.create(
                request: NewSongRequest(name: "Should Not Land In Archive", root: linkedDraftRoot),
                fileManager: fm,
                protectedRoots: [archive]
            )
        ) { error in
            XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .archiveRootIsReadOnly)
        }

        XCTAssertFalse(
            fm.fileExists(atPath: archive.appendingPathComponent("Should Not Land In Archive", isDirectory: true).path)
        )
    }

    func testCreateAllowsOutputOutsideArchiveRoot() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("new-song-ok-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        let drafts = base.appendingPathComponent("drafts", isDirectory: true)
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try fm.createDirectory(at: drafts, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let song = try NewSongFolderCreator.create(
            request: NewSongRequest(name: "Legit Draft", root: drafts),
            fileManager: fm,
            protectedRoots: [archive]
        )
        XCTAssertTrue(fm.fileExists(atPath: song.folderPath.path))
        XCTAssertTrue(song.folderPath.path.hasPrefix(drafts.standardizedFileURL.path))
    }

    func testHiddenAndColonNamesAreRejectedBeforeAnythingIsCreated() throws {
        let fm = FileManager.default
        let root = try makeDirectory(prefix: "new-song-unsafe-names")
        defer { try? fm.removeItem(at: root) }

        // A dot-prefixed folder is hidden from the read-only scanner, so the draft
        // would disappear on the next scan; ":" renders as "/" in Finder.
        for name in [".Hidden Draft", "Mix: Final"] {
            XCTAssertThrowsError(
                try NewSongFolderCreator.create(request: NewSongRequest(name: name, root: root), fileManager: fm),
                name
            ) { error in
                XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .invalidName, name)
            }
        }
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path), [])
    }

    func testTemplateEqualToOutputRootIsRejectedWithoutSongFolder() throws {
        let fm = FileManager.default
        let root = try makeDirectory(prefix: "new-song-template-root")
        defer { try? fm.removeItem(at: root) }

        XCTAssertThrowsError(
            try NewSongFolderCreator.create(
                request: NewSongRequest(name: "Unsafe", root: root, templateFolder: root),
                fileManager: fm
            )
        ) { error in
            XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .templateOverlap)
        }
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Unsafe").path))
    }

    func testTemplateAncestorAndDescendantOfSongFolderAreRejected() throws {
        let fm = FileManager.default
        let base = try makeDirectory(prefix: "new-song-template-overlap")
        defer { try? fm.removeItem(at: base) }
        let root = base.appendingPathComponent("Drafts", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try NewSongFolderCreator.create(
                request: NewSongRequest(name: "Ancestor", root: root, templateFolder: base),
                fileManager: fm
            )
        ) { error in
            XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .templateOverlap)
        }

        let existingSongFolder = root.appendingPathComponent("Descendant", isDirectory: true)
        let nestedTemplate = existingSongFolder.appendingPathComponent("Template", isDirectory: true)
        try fm.createDirectory(at: nestedTemplate, withIntermediateDirectories: true)
        XCTAssertThrowsError(
            try NewSongFolderCreator.create(
                request: NewSongRequest(name: "Descendant", root: root, templateFolder: nestedTemplate),
                fileManager: fm
            )
        ) { error in
            XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .templateOverlap)
        }
    }

    func testMissingAndNonDirectoryTemplatesHaveTypedFailures() throws {
        let fm = FileManager.default
        let root = try makeDirectory(prefix: "new-song-template-types")
        defer { try? fm.removeItem(at: root) }
        let missing = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)

        XCTAssertThrowsError(
            try NewSongFolderCreator.create(
                request: NewSongRequest(name: "Missing", root: root, templateFolder: missing),
                fileManager: fm
            )
        ) { error in
            XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .templateMissing)
        }

        let fileTemplate = root.deletingLastPathComponent().appendingPathComponent("template-\(UUID().uuidString).txt")
        try Data("not a directory".utf8).write(to: fileTemplate)
        defer { try? fm.removeItem(at: fileTemplate) }
        XCTAssertThrowsError(
            try NewSongFolderCreator.create(
                request: NewSongRequest(name: "Unreadable", root: root, templateFolder: fileTemplate),
                fileManager: fm
            )
        ) { error in
            XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .templateUnreadable)
        }
    }

    func testInjectedMidCopyFailureLeavesNoFinalOrStagingFolder() throws {
        let fm = FileManager.default
        let root = try makeDirectory(prefix: "new-song-copy-failure")
        let template = try makeDirectory(prefix: "new-song-copy-template")
        defer {
            try? fm.removeItem(at: root)
            try? fm.removeItem(at: template)
        }
        try Data("one".utf8).write(to: template.appendingPathComponent("one.cpr"))
        try Data("two".utf8).write(to: template.appendingPathComponent("two.txt"))
        let injected = LockedCounter()

        XCTAssertThrowsError(
            try NewSongFolderCreator.create(
                request: NewSongRequest(name: "Atomic", root: root, templateFolder: template),
                fileManager: fm,
                protectedRoots: [],
                copyFailureInjector: { _, _ in
                    if injected.increment() == 2 {
                        throw InjectedCreationError.failure
                    }
                }
            )
        ) { error in
            XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .templateCopyFailed)
        }

        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Atomic").path))
        let leftovers = try fm.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(".niko-music-hub-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testTemplateConflictIsExplicitAndDeterministic() throws {
        let fm = FileManager.default
        let root = try makeDirectory(prefix: "new-song-conflict")
        let template = try makeDirectory(prefix: "new-song-conflict-template")
        defer {
            try? fm.removeItem(at: root)
            try? fm.removeItem(at: template)
        }
        try Data("file conflicts with standard directory".utf8)
            .write(to: template.appendingPathComponent("Mixdown"))

        XCTAssertThrowsError(
            try NewSongFolderCreator.create(
                request: NewSongRequest(name: "Conflict", root: root, templateFolder: template),
                fileManager: fm
            )
        ) { error in
            XCTAssertEqual(error as? NewSongFolderCreator.CreationError, .templateConflict("Mixdown"))
        }
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("Conflict").path))
    }

    func testConcurrentSameNameProducesOneSuccessAndOneCleanConflict() throws {
        let fm = FileManager.default
        let root = try makeDirectory(prefix: "new-song-concurrent")
        defer { try? fm.removeItem(at: root) }
        let results = LockedCreationResults()

        DispatchQueue.concurrentPerform(iterations: 2) { _ in
            do {
                let song = try NewSongFolderCreator.create(
                    request: NewSongRequest(name: "Only Once", root: root),
                    fileManager: .default
                )
                results.append(.success(song.folderPath))
            } catch {
                results.append(.failure(error))
            }
        }

        XCTAssertEqual(results.successCount, 1)
        XCTAssertEqual(results.creationErrors, [.folderExists])
        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("Only Once").path))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: root.path).allSatisfy {
            !$0.hasPrefix(".niko-music-hub-")
        })
    }

    private func makeDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum InjectedCreationError: Error {
    case failure
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

private final class LockedCreationResults: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Result<URL, any Error>] = []

    func append(_ value: Result<URL, any Error>) {
        lock.withLock { values.append(value) }
    }

    var successCount: Int {
        lock.withLock { values.filter { if case .success = $0 { true } else { false } }.count }
    }

    var creationErrors: [NewSongFolderCreator.CreationError] {
        lock.withLock {
            values.compactMap { result in
                guard case let .failure(error) = result else { return nil }
                return error as? NewSongFolderCreator.CreationError
            }
        }
    }
}
