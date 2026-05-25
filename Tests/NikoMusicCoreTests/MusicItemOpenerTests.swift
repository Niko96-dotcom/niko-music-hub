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

        let openResult = try XCTUnwrap(opener.openLatestCPR(for: neon, dryRun: true))
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
        _ = try opener.openLatestCPR(for: neon, dryRun: false)
        XCTAssertEqual(fake.openedCount, 1)
    }
}
