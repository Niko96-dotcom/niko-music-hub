@testable import AppCore
import XCTest

@MainActor
final class ShellJobStatusCenterTests: XCTestCase {
    func testEnqueueFakeJobAppearsInSnapshot() async throws {
        let runner = FakeJobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let job = runner.enqueue(
            title: "Track Mix",
            sourceToolID: "downloader",
            activityVerb: "Downloading",
            cancelTarget: .download
        ) { _ in }

        try await waitUntil { center.jobs.contains { $0.title == job.title } }

        XCTAssertEqual(center.jobs.count, 1)
        let status = try XCTUnwrap(center.jobs.first)
        XCTAssertEqual(status.title, job.title)
        XCTAssertEqual(status.percent, 0.42)
        XCTAssertEqual(status.displayLine, "Downloading “Track Mix” · 42%")
        XCTAssertEqual(status.cancelActionID, job.id.uuidString)
        XCTAssertEqual(status.sourceToolID, "downloader")
        XCTAssertEqual(status.cancelTarget, .download)

        center.cancel(id: try XCTUnwrap(status.cancelActionID))
        XCTAssertEqual(runner.canceledIDs, [job.id])
        try await waitUntil { center.jobs.isEmpty }
        XCTAssertEqual(runner.job(id: job.id)?.state, .canceled)
    }

    func testMultipleJobsTitle() async throws {
        let runner = FakeJobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        _ = runner.enqueue(title: "One", sourceToolID: "downloader") { _ in }
        _ = runner.enqueue(title: "Two", sourceToolID: "stem-separation") { _ in }

        try await waitUntil { center.jobs.count == 2 }
        XCTAssertEqual(center.compactCopy, "2 jobs running")
        XCTAssertEqual(ShellJobStatusCopy.multipleJobsTitle(count: 2), "2 jobs running")
    }

    /// A runner job without a verb shows its title alone, and the keys never reach it.
    func testRunnerJobWithoutVerbOrTargetShowsItsTitle() async throws {
        let runner = FakeJobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        _ = runner.enqueue(title: "Sample Job", sourceToolID: "dev-tool") { _ in }

        try await waitUntil { center.jobs.count == 1 }
        XCTAssertEqual(center.jobs.first?.displayLine, "Sample Job · 42%")
        XCTAssertNil(center.jobs.first?.cancelTarget)
    }

    func testConverterExtraJobCancelMapsToStopAfterCurrent() async throws {
        let runner = FakeJobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let stopFlag = CancelFlag()
        center.setExtraJob(
            sourceID: ShellJobExtraSourceID.converter,
            status: converterRow(),
            cancel: { stopFlag.mark() }
        )

        try await waitUntil { center.jobs.contains { $0.id == ShellJobExtraSourceID.converter } }
        center.cancel(id: ShellJobExtraSourceID.converter)
        XCTAssertTrue(stopFlag.isMarked)
    }

    func testQueuedRunnerUpdateDoesNotRestoreRemovedExtraJob() async throws {
        let runner = FakeJobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        try await Task.sleep(for: .milliseconds(50))
        center.setExtraJob(
            sourceID: ShellJobExtraSourceID.converter,
            status: converterRow()
        )
        XCTAssertTrue(center.jobs.contains { $0.id == ShellJobExtraSourceID.converter })

        // Main stays blocked, so the runner update read off main is queued
        // behind the main-thread removal of the converter row.
        let job = runner.enqueue(title: "Track Mix", sourceToolID: "downloader") { _ in }
        blockMainThread(seconds: 0.3)
        center.setExtraJob(sourceID: ShellJobExtraSourceID.converter, status: nil)

        try await waitUntil { center.jobs.contains { $0.title == job.title } }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(center.jobs.contains { $0.id == ShellJobExtraSourceID.converter })
    }

    func testRealJobRunnerCancelRemovesShellStatus() async throws {
        let runner = JobRunner()
        let center = ShellJobStatusCenter(jobRunner: runner)
        let release = AsyncGate()
        let job = runner.enqueue(title: "Cancelable", sourceToolID: "downloader") { progress in
            progress.update(progress: 0.2, message: "Waiting")
            await release.wait()
        }

        try await waitUntil { center.jobs.contains { $0.title == job.title } }
        XCTAssertEqual(center.jobs.first?.title, job.title)
        center.cancel(id: job.id.uuidString)
        try await waitUntil { center.jobs.isEmpty }
        XCTAssertEqual(runner.job(id: job.id)?.state, .canceled)
        release.open()
    }

    private func converterRow() -> ShellJobStatus {
        ShellJobStatus(
            id: ShellJobExtraSourceID.converter,
            title: "Loop.m4a",
            cancelActionID: ShellJobExtraSourceID.converter,
            activityVerb: "Converting"
        )
    }

    private func blockMainThread(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func waitUntil(
        timeoutAttempts: Int = 100,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<timeoutAttempts {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
        throw ShellJobStatusTestError.timeout
    }
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false

    func mark() {
        lock.withLock { marked = true }
    }

    var isMarked: Bool {
        lock.withLock { marked }
    }
}

private final class FakeJobRunner: JobRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Job] = []
    private var snapshotContinuations: [UUID: AsyncStream<[Job]>.Continuation] = [:]
    private(set) var canceledIDs: [Job.ID] = []

    func listJobs() -> [Job] {
        lock.withLock { stored }
    }

    func job(id: Job.ID) -> Job? {
        lock.withLock { stored.first { $0.id == id } }
    }

    func snapshot() -> [Job] {
        lock.withLock { stored.filter { !$0.state.isTerminal } }
    }

    func allUpdates() -> AsyncStream<[Job]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observerID = UUID()
            let initial = lock.withLock { () -> [Job] in
                snapshotContinuations[observerID] = continuation
                return stored.filter { !$0.state.isTerminal }
            }
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    _ = self?.snapshotContinuations.removeValue(forKey: observerID)
                }
            }
        }
    }

    @discardableResult
    func enqueue(
        title: String,
        sourceToolID: ToolFeatureID,
        activityVerb: String? = nil,
        cancelTarget: InAppJobCancelTarget? = nil,
        operation: @escaping @Sendable (JobProgress) async throws -> Void
    ) -> Job {
        let job = Job(
            sourceToolID: sourceToolID,
            title: title,
            activityVerb: activityVerb,
            cancelTarget: cancelTarget,
            state: .running,
            progress: 0.42,
            message: "Running"
        )
        _ = operation
        lock.withLock {
            stored.append(job)
        }
        emitSnapshot()
        return job
    }

    func cancelJob(id: Job.ID) {
        lock.withLock {
            canceledIDs.append(id)
            if let index = stored.firstIndex(where: { $0.id == id }) {
                stored[index].state = .canceled
                stored[index].message = "Canceled"
                stored[index].finishedAt = Date()
            }
        }
        emitSnapshot()
    }

    private func emitSnapshot() {
        let payload = lock.withLock { () -> ([AsyncStream<[Job]>.Continuation], [Job]) in
            (Array(snapshotContinuations.values), stored.filter { !$0.state.isTerminal })
        }
        for continuation in payload.0 {
            continuation.yield(payload.1)
        }
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    nonisolated func open() {
        Task { await openIsolated() }
    }

    private func openIsolated() {
        guard !isOpen else { return }
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private enum ShellJobStatusTestError: Error {
    case timeout
}
