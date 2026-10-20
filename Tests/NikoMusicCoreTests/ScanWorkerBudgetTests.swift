import XCTest
@testable import NikoMusicCore

/// The full scan walks song folders on a few threads at once: how many depends on the root's volume
/// and on who asked for the scan. Cancelling must stop it within a few folders, not after a batch.
final class ScanWorkerBudgetTests: XCTestCase {
    private func makeArchive(songCount: Int) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("NMH-ScanBudget-\(UUID().uuidString)", isDirectory: true)
        for index in 0..<songCount {
            let folder = root.appendingPathComponent("Song \(index)", isDirectory: true)
            try fm.createDirectory(at: folder.appendingPathComponent("Mixdown"), withIntermediateDirectories: true)
            try Data().write(to: folder.appendingPathComponent("Song \(index).cpr"))
        }
        addTeardownBlock { try? fm.removeItem(at: root) }
        return root
    }

    func testBudgetsAndVolumeLimits() {
        XCTAssertEqual(ScanWorkerBudget.interactive.maximumWorkers, 8)
        XCTAssertEqual(ScanWorkerBudget.background.maximumWorkers, 4)
        // The temporary directory is on the Mac's internal disk.
        XCTAssertEqual(ScanWorkerBudget.volumeLimit(for: FileManager.default.temporaryDirectory), 8)
        // A root whose volume cannot be read gets the cautious external limit.
        let missing = URL(fileURLWithPath: "/Volumes/NMH-No-Such-Volume-\(UUID().uuidString)/Archive")
        XCTAssertEqual(ScanWorkerBudget.volumeLimit(for: missing), 4)
    }

    func testBackgroundBudgetScansTheSameCatalog() throws {
        let root = try makeArchive(songCount: 120)
        let interactive = try MusicArchiveScanner().scan(roots: [root])
        let background = try MusicArchiveScanner(workerBudget: .background).scan(roots: [root])
        var single = MusicArchiveScanner()
        single.workerLimitOverride = 1
        let serial = try single.scan(roots: [root])
        XCTAssertEqual(interactive.songs.count, 120)
        XCTAssertEqual(background.songs, interactive.songs)
        XCTAssertEqual(serial.songs, interactive.songs)
        XCTAssertEqual(background.skippedEntries, interactive.skippedEntries)
    }

    /// Cancelled while the 40th folder starts: the scan throws and stops within the folders already in
    /// flight (about one per thread), not at the end of the batch, which grows to 256 folders.
    func testCancellationStopsInsideABatch() async throws {
        let total = 400
        let root = try makeArchive(songCount: total)
        let probe = CancelProbe(cancelAt: 40)
        var scanner = MusicArchiveScanner()
        scanner.raceHooks.folderWillScan = { _ in probe.folderStarted() }
        let scan = scanner
        let task = Task.detached { () throws -> ScanResult in
            probe.waitUntilArmed()
            return try scan.scan(roots: [root])
        }
        probe.arm { task.cancel() }
        do {
            _ = try await task.value
            XCTFail("A cancelled scan must not return a result")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertGreaterThanOrEqual(probe.started, 40)
        XCTAssertLessThan(probe.started, 40 + 2 * ScanWorkerBudget.interactive.maximumWorkers + 1,
                          "workers kept scanning after the cancellation")
    }
}

/// Counts folder starts across worker threads and cancels the scan once, at a given count.
private final class CancelProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let armed = DispatchSemaphore(value: 0)
    private let cancelAt: Int
    private var count = 0
    private var cancel: (@Sendable () -> Void)?

    init(cancelAt: Int) { self.cancelAt = cancelAt }

    var started: Int { lock.withLock { count } }

    func arm(_ cancel: @escaping @Sendable () -> Void) {
        lock.withLock { self.cancel = cancel }
        armed.signal()
    }

    func waitUntilArmed() { armed.wait() }

    func folderStarted() {
        let action: (@Sendable () -> Void)? = lock.withLock {
            count += 1
            return count == cancelAt ? cancel : nil
        }
        action?()
    }
}
