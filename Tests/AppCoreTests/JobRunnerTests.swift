@testable import AppCore
import XCTest

final class JobRunnerTests: XCTestCase {
    func testCompletesSuccessfulJob() async throws {
        let runner = JobRunner()
        let queued = runner.enqueue(title: "Success", sourceToolID: "dev-tool") { progress in
            progress.update(progress: 0.5, message: "Halfway")
            progress.log("Work started")
        }

        XCTAssertEqual(queued.state, .queued)

        let completed = try await waitForJob(queued.id, in: runner, state: .completed)
        XCTAssertEqual(completed.progress, 1.0)
        XCTAssertEqual(completed.message, "Halfway")
        XCTAssertEqual(completed.logEntries.map(\.message), ["Work started"])
        XCTAssertNotNil(completed.startedAt)
        XCTAssertNotNil(completed.finishedAt)
    }

    func testFailsJobWithMessage() async throws {
        let runner = JobRunner()
        let queued = runner.enqueue(title: "Failure", sourceToolID: "dev-tool") { _ in
            throw SampleJobError.expected
        }

        let failed = try await waitForJob(queued.id, in: runner, state: .failed)
        XCTAssertEqual(failed.message, SampleJobError.expected.localizedDescription)
        XCTAssertNotNil(failed.finishedAt)
    }

    func testCancelTransitionsRunningJob() async throws {
        let runner = JobRunner()
        let queued = runner.enqueue(title: "Cancelable", sourceToolID: "dev-tool") { progress in
            progress.update(progress: 0.2, message: "Waiting")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        _ = try await waitForJob(queued.id, in: runner, state: .running)
        runner.cancelJob(id: queued.id)

        let canceled = try await waitForJob(queued.id, in: runner, state: .canceled)
        XCTAssertEqual(canceled.message, "Canceled")
        XCTAssertNotNil(canceled.finishedAt)
    }

    func testCancelDoesNotRewriteCompletedOrFailedJobs() async throws {
        let runner = JobRunner()
        let completedID = runner.enqueue(title: "Done", sourceToolID: "dev-tool") { _ in }.id
        let failedID = runner.enqueue(title: "Failed", sourceToolID: "dev-tool") { _ in
            throw SampleJobError.expected
        }.id

        let completed = try await waitForJob(completedID, in: runner, state: .completed)
        let failed = try await waitForJob(failedID, in: runner, state: .failed)
        runner.cancelJob(id: completedID)
        runner.cancelJob(id: failedID)

        XCTAssertEqual(runner.job(id: completedID), completed)
        XCTAssertEqual(runner.job(id: failedID), failed)
    }

    func testImmediateCompletionRemovesTaskHandle() async throws {
        let runner = JobRunner()
        let id = runner.enqueue(title: "Immediate", sourceToolID: "dev-tool") { _ in }.id

        _ = try await waitForJob(id, in: runner, state: .completed)
        try await waitUntil { runner.activeTaskCount == 0 }
        XCTAssertEqual(runner.activeTaskCount, 0)
    }

    func testLogRetentionKeepsNewestEntries() async throws {
        let runner = JobRunner(maximumLogEntriesPerJob: 3)
        let id = runner.enqueue(title: "Logs", sourceToolID: "dev-tool") { progress in
            for index in 0..<5 {
                progress.log("entry-\(index)")
            }
        }.id

        let completed = try await waitForJob(id, in: runner, state: .completed)
        XCTAssertEqual(completed.logEntries.map(\.message), ["entry-2", "entry-3", "entry-4"])
    }

    func testLogRetentionHonorsByteBudgetAndKeepsNewestEntries() async throws {
        let runner = JobRunner(
            maximumLogEntriesPerJob: 10,
            maximumLogBytesPerJob: 12,
            maximumLogEntryBytes: 12
        )
        let id = runner.enqueue(title: "Logs", sourceToolID: "dev-tool") { progress in
            progress.log("first")
            progress.log("second")
            progress.log("third")
        }.id

        let completed = try await waitForJob(id, in: runner, state: .completed)
        XCTAssertEqual(completed.logEntries.map(\.message), ["second", "third"])
        XCTAssertLessThanOrEqual(
            completed.logEntries.reduce(into: 0) { $0 += $1.message.utf8.count },
            12
        )
    }

    func testFailureMessageIsBoundedWithoutChangingTerminalState() async throws {
        let runner = JobRunner(maximumSnapshotTextBytes: 12)
        let id = runner.enqueue(title: "Failure", sourceToolID: "dev-tool") { _ in
            throw LongFailureError()
        }.id

        let failed = try await waitForJob(id, in: runner, state: .failed)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertLessThanOrEqual(failed.message.utf8.count, 12)
        XCTAssertTrue(failed.message.hasSuffix("…"))
    }

    func testUpdateStreamEmitsTerminalStateAndFinishes() async throws {
        let runner = JobRunner()
        let release = AsyncGate()
        let id = runner.enqueue(title: "Stream", sourceToolID: "dev-tool") { progress in
            progress.update(progress: 0.5, message: "Halfway")
            await release.wait()
        }.id
        let stream = runner.updates(for: id)
        let collector = Task { () -> [JobState] in
            var states: [JobState] = []
            for await update in stream {
                states.append(update.state)
            }
            return states
        }

        _ = try await waitForJob(id, in: runner, state: .running)
        release.open()
        let states = await collector.value

        XCTAssertEqual(states.last, .completed)
        XCTAssertTrue(states.contains(.running))
        XCTAssertEqual(states.filter(\.isTerminal).count, 1)
    }

    func testSlowUpdateStreamCoalescesToLatestFailedSnapshot() async throws {
        let runner = JobRunner()
        let release = AsyncGate()
        let id = runner.enqueue(title: "Stream", sourceToolID: "dev-tool") { progress in
            await release.wait()
            for index in 0..<1_000 {
                progress.update(progress: Double(index) / 1_000, message: "Update \(index)")
                progress.log("log-\(index)")
            }
            throw SampleJobError.expected
        }.id
        let stream = runner.updates(for: id)

        _ = try await waitForJob(id, in: runner, state: .running)
        release.open()
        _ = try await waitForJob(id, in: runner, state: .failed)

        var iterator = stream.makeAsyncIterator()
        let terminal = await iterator.next()
        XCTAssertEqual(terminal?.state, .failed)
        XCTAssertEqual(terminal?.message, SampleJobError.expected.localizedDescription)
        let following = await iterator.next()
        XCTAssertNil(following)
    }

    func testTenThousandImmediateJobsRemainBoundedAndReleaseHandles() async throws {
        let runner = JobRunner(maximumRetainedJobs: 100)
        for index in 0..<10_000 {
            runner.enqueue(title: "Job \(index)", sourceToolID: "stress") { _ in }
        }

        try await waitUntil(timeoutIterations: 2_000) {
            runner.activeTaskCount == 0
        }
        XCTAssertLessThanOrEqual(runner.listJobs().count, 100)
        XCTAssertEqual(runner.activeTaskCount, 0)
        XCTAssertTrue(runner.listJobs().allSatisfy { $0.state.isTerminal })
    }

    private func waitForJob(
        _ id: Job.ID,
        in runner: JobRunner,
        state: JobState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Job {
        for _ in 0..<100 {
            if let job = runner.job(id: id), job.state == state {
                return job
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for job state \(state)", file: file, line: line)
        throw SampleJobError.timeout
    }

    private func waitUntil(
        timeoutIterations: Int = 100,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @Sendable () -> Bool
    ) async throws {
        for _ in 0..<timeoutIterations {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
        throw SampleJobError.timeout
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

private enum SampleJobError: LocalizedError {
    case expected
    case timeout

    var errorDescription: String? {
        switch self {
        case .expected:
            "Expected failure"
        case .timeout:
            "Timed out"
        }
    }
}

private struct LongFailureError: LocalizedError {
    var errorDescription: String? {
        String(repeating: "failure", count: 100)
    }
}
