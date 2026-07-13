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
}

public extension JobRunning {
    /// Compatibility stream for lightweight test doubles. `JobRunner` provides
    /// a lock-backed event stream and does not use polling.
    func updates(for id: Job.ID) -> AsyncStream<Job> {
        AsyncStream { continuation in
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
}
