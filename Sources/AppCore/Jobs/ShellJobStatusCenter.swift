import Combine
import Foundation

/// Merges `JobRunner` snapshots with converter / archive extra sources for the shell jobs row.
public final class ShellJobStatusCenter: ObservableObject, @unchecked Sendable {
    @Published public private(set) var jobs: [ShellJobStatus] = []

    public var compactCopy: String {
        switch jobs.count {
        case 0:
            return ""
        case 1:
            return jobs[0].displayLine
        default:
            return ShellJobStatusCopy.multipleJobsTitle(count: jobs.count)
        }
    }

    private let jobRunner: any JobRunning
    private let lock = NSLock()
    private var runnerJobs: [ShellJobStatus] = []
    private var extraJobs: [String: ShellJobStatus] = [:]
    private var extraCancels: [String: @Sendable () -> Void] = [:]
    private var observeTask: Task<Void, Never>?

    public init(jobRunner: any JobRunning) {
        self.jobRunner = jobRunner
        observeTask = Task { [weak self] in
            for await snapshot in jobRunner.allUpdates() {
                self?.applyRunnerSnapshot(snapshot)
            }
        }
    }

    deinit {
        observeTask?.cancel()
    }

    public func setExtraJob(
        sourceID: String,
        status: ShellJobStatus?,
        cancel: (@Sendable () -> Void)? = nil
    ) {
        lock.withLock {
            if let status {
                extraJobs[sourceID] = status
                if let cancel {
                    extraCancels[sourceID] = cancel
                }
            } else {
                extraJobs.removeValue(forKey: sourceID)
                extraCancels.removeValue(forKey: sourceID)
            }
        }
        republish()
    }

    public func cancel(id: String) {
        let extra: (@Sendable () -> Void)? = lock.withLock {
            extraCancels[id]
        }
        if let extra {
            extra()
            return
        }
        if let uuid = UUID(uuidString: id) {
            jobRunner.cancelJob(id: uuid)
        }
    }

    private func applyRunnerSnapshot(_ jobs: [Job]) {
        lock.withLock {
            runnerJobs = jobs.map(ShellJobStatus.fromJob)
        }
        republish()
    }

    private func republish() {
        let merged = lock.withLock {
            runnerJobs + extraJobs.keys.sorted().compactMap { extraJobs[$0] }
        }
        if Thread.isMainThread {
            self.jobs = merged
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.jobs = merged
            }
        }
    }
}
