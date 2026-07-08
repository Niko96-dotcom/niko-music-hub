import XCTest
@testable import NikoMusicCore

private final class FakeWorkspace: WorkspaceOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var opened: [URL] = []
    private var revealed: [URL] = []

    func open(_ url: URL) -> Bool {
        lock.lock()
        opened.append(url)
        lock.unlock()
        return true
    }

    func revealInFinder(_ url: URL) {
        lock.lock()
        revealed.append(url)
        lock.unlock()
    }

    var openedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return opened.count
    }
}

private final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func contains(where predicate: (String) -> Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return lines.contains(where: predicate)
    }
}

final class MusicItemOpenerTests: XCTestCase {
    func testDryRunDoesNotCallWorkspace() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })

        let fake = FakeWorkspace()
        let logs = LogCollector()
        let opener = MusicItemOpener(workspace: fake) { logs.append($0) }

        let openResult = try XCTUnwrap(
            opener.openLatestCPR(for: neon, dryRun: true, allowedRoots: [CubaseFixtures.archiveRoot])
        )
        XCTAssertTrue(openResult.dryRun)
        XCTAssertTrue(openResult.path.contains("Neon Hook"))
        XCTAssertTrue(openResult.path.hasSuffix(".cpr"))
        XCTAssertEqual(fake.openedCount, 0)
        XCTAssertTrue(logs.contains(where: { $0.contains("[dry-run] open CPR:") }))
    }

    func testNonDryRunUsesWorkspace() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })

        let fake = FakeWorkspace()
        let opener = MusicItemOpener(workspace: fake)
        _ = try opener.openLatestCPR(for: neon, dryRun: false, allowedRoots: [CubaseFixtures.archiveRoot])
        XCTAssertEqual(fake.openedCount, 1)
    }

    func testOpenRejectsCPROutsideAllowedRoots() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })

        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("music-item-opener-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideRoot) }

        let fake = FakeWorkspace()
        let opener = MusicItemOpener(workspace: fake)
        XCTAssertThrowsError(
            try opener.openLatestCPR(for: neon, dryRun: false, allowedRoots: [outsideRoot])
        ) { error in
            guard case MusicItemOpenerError.pathOutsideAllowedRoots = error else {
                XCTFail("Expected pathOutsideAllowedRoots, got \(error)")
                return
            }
        }
        XCTAssertEqual(fake.openedCount, 0)
    }

    func testOpenRejectsWhenAllowedRootsEmpty() throws {
        try CubaseFixtures.ensureGenerated()
        let scanner = CubaseArchiveScanner()
        let result = try scanner.scan(roots: [CubaseFixtures.archiveRoot])
        let neon = try XCTUnwrap(result.songs.first { $0.displayTitle == "Neon Hook" })

        let fake = FakeWorkspace()
        let opener = MusicItemOpener(workspace: fake)
        XCTAssertThrowsError(
            try opener.openLatestCPR(for: neon, dryRun: true, allowedRoots: [])
        ) { error in
            guard case MusicItemOpenerError.pathOutsideAllowedRoots = error else {
                XCTFail("Expected pathOutsideAllowedRoots, got \(error)")
                return
            }
        }
        XCTAssertEqual(fake.openedCount, 0)
    }
}
