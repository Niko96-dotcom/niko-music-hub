import Foundation

public protocol JobRunning: Sendable {
    func listJobs() -> [Job]

    func job(id: Job.ID) -> Job?

    /// Emits the current job snapshot and subsequent changes until terminal.
    func updates(for id: Job.ID) -> AsyncStream<Job>

    @discardableResult
    func enqueue(
        title: String,
        sourceToolID: ToolFeatureID,
        operation: @escaping @Sendable (JobProgress) async throws -> Void
    ) -> Job

    func cancelJob(id: Job.ID)

    /// Non-terminal jobs in enqueue order.
    func snapshot() -> [Job]

    /// Current non-terminal snapshot, then subsequent changes.
    func allUpdates() -> AsyncStream<[Job]>

    /// True while any job's operation is still running, including a cancelled
    /// job that has not unwound yet (quit waits for this, ADR-019).
    var hasUnfinishedWork: Bool { get }
}

public extension JobRunning {
    /// Compatibility stream for lightweight test doubles. `JobRunner` provides
    /// a lock-backed event stream and does not use polling.
    func updates(for id: Job.ID) -> AsyncStream<Job> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                while !Task.isCancelled {
                    guard let current = job(id: id) else {
                        continuation.finish()
                        return
                    }
                    continuation.yield(current)
                    if current.state.isTerminal {
                        continuation.finish()
                        return
                    }
                    do {
                        try await Task.sleep(for: .milliseconds(100))
                    } catch {
                        continuation.finish()
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func snapshot() -> [Job] {
        listJobs().filter { !$0.state.isTerminal }
    }

    /// Test doubles only: the snapshot cannot see a cancelled job that is still
    /// unwinding. A real runner overrides this (see `JobRunner`).
    var hasUnfinishedWork: Bool {
        !snapshot().isEmpty
    }

    /// Compatibility stream for lightweight test doubles. `JobRunner` notifies on each publish.
    func allUpdates() -> AsyncStream<[Job]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                var last: [Job]?
                while !Task.isCancelled {
                    let current = snapshot()
                    if last == nil || current != last {
                        continuation.yield(current)
                        last = current
                    }
                    do {
                        try await Task.sleep(for: .milliseconds(100))
                    } catch {
                        continuation.finish()
                        return
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
