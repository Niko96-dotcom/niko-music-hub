import NikoMusicCore
import XCTest

final class ProjectSourceInventoryTests: XCTestCase {
    private var root: URL!
    private var folder: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-inventory-\(UUID().uuidString)", isDirectory: true)
        folder = root.appendingPathComponent("Mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions so the temporary tree can be removed after the unreadable-subfolder case.
        if let enumerator = FileManager.default.enumerator(atPath: root.path) {
            for case let relative as String in enumerator {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent(relative).path)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    func testCompleteInventoryCarriesFullPrecisionSizeAndTimestampFromDisk() throws {
        let cpr = try writeProjectFile("Mirror-03.cpr", bytes: 1_234)
        let fractional = Date(timeIntervalSinceReferenceDate: 805_032_438.412_305_4)
        try FileManager.default.setAttributes([.modificationDate: fractional], ofItemAtPath: cpr.path)
        let onDisk = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: cpr.path)[.modificationDate] as? Date)
        guard onDisk.timeIntervalSinceReferenceDate != onDisk.timeIntervalSinceReferenceDate.rounded(.down) else {
            throw XCTSkip("this volume floors modification times to whole seconds; the precision case cannot be exercised here")
        }

        let outcome = try ProjectSourceInventory().collect(in: folder, for: song())

        guard case .complete(let evidence, let versions) = outcome else {
            return XCTFail("expected complete inventory, got \(outcome)")
        }
        XCTAssertEqual(versions.map(\.fileName), ["Mirror-03.cpr"])
        XCTAssertEqual(evidence.cubaseFiles, [ProjectFileIdentity(name: "Mirror-03.cpr", byteCount: 1_234, modifiedAt: onDisk)])
        XCTAssertEqual(evidence.normalizedFolderName, "mirror")
    }

    func testMissingFolderIsUnavailable() throws {
        try FileManager.default.removeItem(at: folder)

        XCTAssertEqual(try ProjectSourceInventory().collect(in: folder, for: song()), .unavailable(.folderUnavailable))
    }

    func testFolderReplacedByFileIsUnavailable() throws {
        try FileManager.default.removeItem(at: folder)
        try Data("not a folder".utf8).write(to: folder)

        XCTAssertEqual(try ProjectSourceInventory().collect(in: folder, for: song()), .unavailable(.folderUnavailable))
    }

    func testListedVersionThatVanishedIsIncomplete() throws {
        let kept = try writeProjectFile("Mirror.cpr", bytes: 10)
        let vanished = try writeProjectFile("Mirror-01.cpr", bytes: 20)
        let stale = song(listing: [kept, vanished])
        try FileManager.default.removeItem(at: vanished)

        XCTAssertEqual(
            try ProjectSourceInventory().collect(in: folder, for: stale),
            .incomplete(.listedVersionMissing(fileName: "Mirror-01.cpr"))
        )
    }

    func testMissingSizeOrModificationDateIsIncompleteNeverInvented() throws {
        _ = try writeProjectFile("Mirror.cpr", bytes: 10)
        let real: ProjectSourceInventory.FileAttributesReader = { url in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return .init(
                byteCount: (attributes[.size] as? NSNumber).map { Int64(truncating: $0) },
                modificationDate: attributes[.modificationDate] as? Date
            )
        }
        let cases: [(String, ProjectSourceInventory.FileAttributesReader)] = [
            ("no modification date", { url in
                var attributes = try real(url)
                attributes.modificationDate = nil
                return attributes
            }),
            ("no size", { url in
                var attributes = try real(url)
                attributes.byteCount = nil
                return attributes
            }),
            ("read failure", { _ in throw CocoaError(.fileReadNoPermission) }),
        ]

        for (label, reader) in cases {
            XCTAssertEqual(
                try ProjectSourceInventory(readAttributes: reader).collect(in: folder, for: song()),
                .incomplete(.attributesUnreadable(relativePath: "Mirror.cpr")),
                label
            )
        }
    }

    func testUnreadableSubfolderIsIncompleteEvenThoughTopLevelListingSucceeds() throws {
        try XCTSkipIf(geteuid() == 0, "root ignores directory permissions")
        _ = try writeProjectFile("Mirror.cpr", bytes: 10)
        let nested = folder.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: nested.path)

        XCTAssertEqual(
            try ProjectSourceInventory().collect(in: folder, for: song()),
            .incomplete(.enumerationFailed(relativePath: "Nested"))
        )
    }

    func testDanglingProjectFileSymlinkIsIncompleteWhileTheScannerStillSkipsIt() throws {
        _ = try writeProjectFile("Mirror.cpr", bytes: 10)
        let dangling = folder.appendingPathComponent("Link.cpr")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: folder.appendingPathComponent("gone.cpr"))
        let cachedListingWithoutTheLink = song(listing: [folder.appendingPathComponent("Mirror.cpr")])

        // Ordinary scanning keeps ignoring it, as before.
        XCTAssertEqual(try ProjectVersionDetector().detectVersions(in: folder).map(\.fileName), ["Mirror.cpr"])
        // Identity must not be derived from a folder whose eligible project file cannot be read.
        XCTAssertEqual(
            try ProjectSourceInventory().collect(in: folder, for: cachedListingWithoutTheLink),
            .incomplete(.unreadableProjectFile(relativePath: "Link.cpr"))
        )
    }

    func testDirectoryNamedLikeAProjectFileStaysIgnoredLikeTheScannerDoes() throws {
        _ = try writeProjectFile("Mirror.cpr", bytes: 10)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Folder.cpr"), withIntermediateDirectories: true)

        XCTAssertEqual(try ProjectVersionDetector().detectVersions(in: folder).map(\.fileName), ["Mirror.cpr"])
        guard case .complete(let evidence, _) = try ProjectSourceInventory().collect(in: folder, for: song()) else {
            return XCTFail("a directory is not a project file and must not block the inventory")
        }
        XCTAssertEqual(evidence.cubaseFiles.map(\.normalizedName), ["mirror.cpr"])
    }

    func testDiskTruthIncludesUnlistedProjectFilesAndKeepsScannerFormatRules() throws {
        let listed = try writeProjectFile("Mirror.cpr", bytes: 10)
        _ = try writeProjectFile("Mirror.als", bytes: 11)
        _ = try writeProjectFile("Mirror.bak.cpr", bytes: 12)
        _ = try writeProjectFile("Mirror-02.cpr", bytes: 13)

        let outcome = try ProjectSourceInventory().collect(in: folder, for: song(listing: [listed]))

        guard case .complete(let evidence, _) = outcome else {
            return XCTFail("expected complete inventory, got \(outcome)")
        }
        XCTAssertEqual(Set(evidence.cubaseFiles.map(\.normalizedName)), ["mirror.cpr", "mirror.als", "mirror-02.cpr"])
        XCTAssertTrue(evidence.cubaseFiles.allSatisfy { $0.byteCount > 0 })
    }

    func testCancellationPropagatesInsteadOfBecomingUnavailable() async throws {
        _ = try writeProjectFile("Mirror.cpr", bytes: 10)
        let gate = Gate()
        let folder = try XCTUnwrap(self.folder)
        let song = song()
        let task = Task { () throws -> ProjectSourceInventory.Outcome in
            await gate.wait()
            return try ProjectSourceInventory().collect(in: folder, for: song)
        }
        task.cancel()
        await gate.open()

        do {
            let outcome = try await task.value
            XCTFail("expected cancellation to propagate, got \(outcome)")
        } catch {
            XCTAssertTrue(error is CancellationError, "unexpected error \(error)")
        }
    }

    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    private func writeProjectFile(_ name: String, bytes: Int) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    /// A song listing the given files (or everything the scanner would list) as its versions.
    private func song(listing: [URL]? = nil) -> Song {
        let versions: [ProjectVersion]
        if let listing {
            versions = listing.map { ProjectVersion(filePath: $0, fileName: $0.lastPathComponent, modifiedAt: .distantPast) }
        } else {
            versions = (try? ProjectVersionDetector().detectVersions(in: folder)) ?? []
        }
        return Song(
            folderPath: folder,
            originalFolderName: folder.lastPathComponent,
            displayTitle: folder.lastPathComponent,
            projectVersions: versions
        )
    }
}
