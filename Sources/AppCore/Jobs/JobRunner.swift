import Foundation

public struct JobProgress: Sendable {
    private let updateHandler: @Sendable (Double, String?) -> Void
    private let logHandler: @Sendable (String) -> Void
    private let outputHandler: @Sendable ([URL]) -> Void

    public init(
        updateHandler: @escaping @Sendable (Double, String?) -> Void,
        logHandler: @escaping @Sendable (String) -> Void,
        outputHandler: @escaping @Sendable ([URL]) -> Void = { _ in }
    ) {
        self.updateHandler = updateHandler
        self.logHandler = logHandler
        self.outputHandler = outputHandler
    }

    public func update(progress: Double, message: String? = nil) {
        updateHandler(min(max(progress, 0), 1), message)
    }

    public func log(_ message: String) {
        logHandler(message)
    }

    public func setOutputFileURLs(_ urls: [URL]) {
        outputHandler(urls)
    }
}

public final class JobRunner: JobRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let maximumRetainedJobs: Int
    private let maximumLogEntriesPerJob: Int
    private let maximumLogBytesPerJob: Int
    private let maximumLogEntryBytes: Int
    private let maximumSnapshotTextBytes: Int
    private var jobs: [Job.ID: Job] = [:]
    private var order: [Job.ID] = []
    private var tasks: [Job.ID: Task<Void, Never>] = [:]
    private var observers: [Job.ID: [UUID: AsyncStream<Job>.Continuation]] = [:]
    private var retainedLogBytes: [Job.ID: Int] = [:]

    public init(
        maximumRetainedJobs: Int = 500,
        maximumLogEntriesPerJob: Int = 1_000,
        maximumLogBytesPerJob: Int = 256 * 1_024,
        maximumLogEntryBytes: Int = 16 * 1_024,
        maximumSnapshotTextBytes: Int = 16 * 1_024
    ) {
        self.maximumRetainedJobs = max(1, maximumRetainedJobs)
        self.maximumLogEntriesPerJob = max(1, maximumLogEntriesPerJob)
        let logByteBudget = max(1, maximumLogBytesPerJob)
        self.maximumLogBytesPerJob = logByteBudget
        self.maximumLogEntryBytes = min(max(1, maximumLogEntryBytes), logByteBudget)
        self.maximumSnapshotTextBytes = max(1, maximumSnapshotTextBytes)
    }

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

    public func updates(for id: Job.ID) -> AsyncStream<Job> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observerID = UUID()
            let terminalSnapshot = lock.withLock { () -> Job? in
                guard let current = jobs[id] else { return nil }
                continuation.yield(current)
                if current.state.isTerminal {
                    return current
                }
                observers[id, default: [:]][observerID] = continuation
                return nil
            }

            if terminalSnapshot != nil || job(id: id) == nil {
                continuation.finish()
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeObserver(id: observerID, jobID: id)
            }
        }
    }

    @discardableResult
    public func enqueue(
        title: String,
        sourceToolID: ToolFeatureID,
        operation: @escaping @Sendable (JobProgress) async throws -> Void
    ) -> Job {
        let job = Job(
            sourceToolID: sourceToolID,
            title: boundedText(title, maximumUTF8Bytes: maximumSnapshotTextBytes),
            message: "Queued"
        )
        lock.withLock {
            jobs[job.id] = job
            order.append(job.id)
        }

        let progress = JobProgress(
            updateHandler: { [weak self] progress, message in
                guard let self else { return }
                let boundedMessage = message.map {
                    self.boundedText($0, maximumUTF8Bytes: self.maximumSnapshotTextBytes)
                }
                self.mutateActiveJob(id: job.id) { current in
                    current.progress = progress
                    if let boundedMessage {
                        current.message = boundedMessage
                    }
                }
            },
            logHandler: { [weak self] message in
                self?.appendLog(message, to: job.id)
            },
            outputHandler: { [weak self] urls in
                self?.mutateActiveJob(id: job.id) { current in
                    current.outputFileURLs = urls
                }
            }
        )

        let startGate = JobStartGate()
        let task = Task { [weak self] in
            await startGate.wait()
            guard let self else { return }
            defer { self.removeTask(id: job.id) }
            self.markRunning(id: job.id)
            do {
                try Task.checkCancellation()
                try await operation(progress)
                try Task.checkCancellation()
                self.markCompleted(id: job.id)
            } catch is CancellationError {
                self.markCanceled(id: job.id)
            } catch {
                self.markFailed(id: job.id, message: error.localizedDescription)
            }
        }

        lock.withLock {
            tasks[job.id] = task
        }
        startGate.open()
        return job
    }

    public func cancelJob(id: Job.ID) {
        let outcome = lock.withLock { () -> (Task<Void, Never>?, Job?, [AsyncStream<Job>.Continuation]) in
            guard var current = jobs[id], !current.state.isTerminal else { return (nil, nil, []) }
            current.state = .canceled
            current.message = "Canceled"
            current.finishedAt = Date()
            jobs[id] = current
            let continuations = terminalObserversLocked(for: id)
            pruneTerminalJobsLocked()
            return (tasks[id], current, continuations)
        }
        outcome.0?.cancel()
        publish(outcome.1, to: outcome.2, finish: true)
    }

    var activeTaskCount: Int {
        lock.withLock { tasks.count }
    }

    private func markRunning(id: Job.ID) {
        mutateJob(id: id) { job in
            guard job.state == .queued else { return false }
            job.state = .running
            job.startedAt = Date()
            job.message = "Running"
            return true
        }
    }

    private func markCompleted(id: Job.ID) {
        mutateJob(id: id) { job in
            guard job.state == .running else { return false }
            job.state = .completed
            job.progress = 1
            job.message = job.message.isEmpty ? "Completed" : job.message
            job.finishedAt = Date()
            return true
        }
    }

    private func markFailed(id: Job.ID, message: String) {
        let boundedMessage = boundedText(message, maximumUTF8Bytes: maximumSnapshotTextBytes)
        mutateJob(id: id) { job in
            guard job.state == .running else { return false }
            job.state = .failed
            job.message = boundedMessage
            job.finishedAt = Date()
            return true
        }
    }

    private func markCanceled(id: Job.ID) {
        mutateJob(id: id) { job in
            guard !job.state.isTerminal else { return false }
            job.state = .canceled
            job.message = "Canceled"
            job.finishedAt = Date()
            return true
        }
    }

    private func mutateActiveJob(id: Job.ID, update: (inout Job) -> Void) {
        mutateJob(id: id) { job in
            guard !job.state.isTerminal else { return false }
            update(&job)
            return true
        }
    }

    private func appendLog(_ message: String, to id: Job.ID) {
        let boundedMessage = boundedText(message, maximumUTF8Bytes: maximumLogEntryBytes)
        let messageBytes = boundedMessage.utf8.count
        mutateActiveJob(id: id) { job in
            var byteCount = retainedLogBytes[id] ?? job.logEntries.reduce(into: 0) {
                $0 += $1.message.utf8.count
            }
            job.logEntries.append(JobLogEntry(message: boundedMessage))
            byteCount += messageBytes
            while job.logEntries.count > maximumLogEntriesPerJob || byteCount > maximumLogBytesPerJob {
                let removed = job.logEntries.removeFirst()
                byteCount -= removed.message.utf8.count
            }
            retainedLogBytes[id] = byteCount
        }
    }

    private func mutateJob(id: Job.ID, update: (inout Job) -> Bool) {
        let outcome = lock.withLock { () -> (Job?, [AsyncStream<Job>.Continuation], Bool) in
            guard var current = jobs[id], update(&current) else { return (nil, [], false) }
            jobs[id] = current
            let isTerminal = current.state.isTerminal
            let continuations = isTerminal
                ? terminalObserversLocked(for: id)
                : Array(observers[id]?.values ?? [:].values)
            if isTerminal {
                pruneTerminalJobsLocked()
            }
            return (current, continuations, isTerminal)
        }
        publish(outcome.0, to: outcome.1, finish: outcome.2)
    }

    private func publish(
        _ job: Job?,
        to continuations: [AsyncStream<Job>.Continuation],
        finish: Bool
    ) {
        guard let job else { return }
        for continuation in continuations {
            continuation.yield(job)
            if finish {
                continuation.finish()
            }
        }
    }

    private func terminalObserversLocked(for id: Job.ID) -> [AsyncStream<Job>.Continuation] {
        let continuations = Array(observers[id]?.values ?? [:].values)
        observers.removeValue(forKey: id)
        return continuations
    }

    private func removeObserver(id: UUID, jobID: Job.ID) {
        lock.withLock {
            observers[jobID]?.removeValue(forKey: id)
            if observers[jobID]?.isEmpty == true {
                observers.removeValue(forKey: jobID)
            }
        }
    }

    private func removeTask(id: Job.ID) {
        _ = lock.withLock {
            tasks.removeValue(forKey: id)
        }
    }

    private func pruneTerminalJobsLocked() {
        guard order.count > maximumRetainedJobs else { return }
        var retained: [Job.ID] = []
        retained.reserveCapacity(order.count)
        var removableCount = order.count - maximumRetainedJobs
        for id in order {
            if removableCount > 0, jobs[id]?.state.isTerminal == true {
                jobs.removeValue(forKey: id)
                observers.removeValue(forKey: id)
                retainedLogBytes.removeValue(forKey: id)
                removableCount -= 1
            } else {
                retained.append(id)
            }
        }
        order = retained
    }

    private func boundedText(_ text: String, maximumUTF8Bytes: Int) -> String {
        guard text.utf8.count > maximumUTF8Bytes else { return text }

        let suffix = "…"
        guard maximumUTF8Bytes >= suffix.utf8.count else {
            return String(text[..<utf8EndIndex(in: text, maximumBytes: maximumUTF8Bytes)])
        }
        let prefix = String(text[..<utf8EndIndex(
            in: text,
            maximumBytes: maximumUTF8Bytes - suffix.utf8.count
        )])
        return prefix + suffix
    }

    private func utf8EndIndex(in text: String, maximumBytes: Int) -> String.Index {
        guard maximumBytes > 0 else { return text.startIndex }
        let utf8 = text.utf8
        guard utf8.count > maximumBytes else { return text.endIndex }
        var end = utf8.index(utf8.startIndex, offsetBy: maximumBytes)
        while end != utf8.startIndex, (utf8[end] & 0b1100_0000) == 0b1000_0000 {
            end = utf8.index(before: end)
        }
        return end
    }
}

private final class JobStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func open() {
        let storedWaiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            guard !isOpen else { return [] }
            isOpen = true
            let stored = waiters
            waiters.removeAll()
            return stored
        }
        storedWaiters.forEach { $0.resume() }
    }
}
