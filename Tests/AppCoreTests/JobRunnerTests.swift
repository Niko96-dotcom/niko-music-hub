import AppCore
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
