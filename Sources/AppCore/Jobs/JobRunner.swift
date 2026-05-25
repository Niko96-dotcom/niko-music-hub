import Foundation

public struct JobProgress: Sendable {
    private let updateHandler: @Sendable (Double, String?) -> Void
    private let logHandler: @Sendable (String) -> Void

    public init(
        updateHandler: @escaping @Sendable (Double, String?) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) {
        self.updateHandler = updateHandler
        self.logHandler = logHandler
    }

    public func update(progress: Double, message: String? = nil) {
        updateHandler(min(max(progress, 0), 1), message)
    }

    public func log(_ message: String) {
        logHandler(message)
    }
}

public final class JobRunner: JobRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [Job.ID: Job] = [:]
    private var order: [Job.ID] = []
    private var tasks: [Job.ID: Task<Void, Never>] = [:]

    public init() {}

    public func listJobs() -> [Job] {
        lock.withLock {
            order.compactMap { jobs[$0] }
        }
    }

    public func job(id: Job.ID) -> Job? {
        lock.withLock {
            jobs[id]
        }
    }

    @discardableResult
    public func enqueue(
        title: String,
        sourceToolID: ToolFeatureID,
        operation: @escaping @Sendable (JobProgress) async throws -> Void
    ) -> Job {
        let job = Job(sourceToolID: sourceToolID, title: title, message: "Queued")
        lock.withLock {
            jobs[job.id] = job
            order.append(job.id)
        }

        let progress = JobProgress(
            updateHandler: { [weak self] progress, message in
                self?.updateJob(id: job.id) { current in
                    current.progress = progress
                    if let message {
                        current.message = message
                    }
                }
            },
            logHandler: { [weak self] message in
                self?.updateJob(id: job.id) { current in
                    current.logEntries.append(JobLogEntry(message: message))
                }
            }
        )

        let task = Task { [weak self] in
            self?.markRunning(id: job.id)
            do {
                try Task.checkCancellation()
                try await operation(progress)
                try Task.checkCancellation()
                self?.markCompleted(id: job.id)
            } catch is CancellationError {
                self?.markCanceled(id: job.id)
            } catch {
                self?.markFailed(id: job.id, message: error.localizedDescription)
            }
        }

        lock.withLock {
            tasks[job.id] = task
        }

        return job
    }

    public func cancelJob(id: Job.ID) {
        let task = lock.withLock {
            tasks[id]
        }
        task?.cancel()
        markCanceled(id: id)
    }

    private func markRunning(id: Job.ID) {
        updateJob(id: id) { job in
            guard job.state == .queued else { return }
            job.state = .running
            job.startedAt = Date()
            job.message = "Running"
        }
    }

    private func markCompleted(id: Job.ID) {
        updateJob(id: id) { job in
            guard job.state != .canceled else { return }
            job.state = .completed
            job.progress = 1
            job.message = job.message.isEmpty ? "Completed" : job.message
            job.finishedAt = Date()
        }
    }

    private func markFailed(id: Job.ID, message: String) {
        updateJob(id: id) { job in
            guard job.state != .canceled else { return }
            job.state = .failed
            job.message = message
            job.finishedAt = Date()
        }
    }

    private func markCanceled(id: Job.ID) {
        updateJob(id: id) { job in
            guard job.state != .completed else { return }
            job.state = .canceled
            job.message = "Canceled"
            job.finishedAt = Date()
        }
    }

    private func updateJob(id: Job.ID, update: (inout Job) -> Void) {
        lock.withLock {
            guard var job = jobs[id] else { return }
            update(&job)
            jobs[id] = job
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
