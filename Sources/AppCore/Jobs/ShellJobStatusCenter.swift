import Combine
import Foundation

/// Merges `JobRunner` snapshots with converter / archive extra sources for the shell jobs row,
/// and is the one registry of work quit must not cut off silently (ADR-019).
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
    private var extraQuitCancels: [String: @Sendable () -> Void] = [:]
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

    /// `quitCancel` replaces `cancel` when quit stops the work (ADR-019); pass it
    /// when the jobs-strip cancel only asks for confirmation.
    public func setExtraJob(
        sourceID: String,
        status: ShellJobStatus?,
        cancel: (@Sendable () -> Void)? = nil,
        quitCancel: (@Sendable () -> Void)? = nil
    ) {
        lock.withLock {
            if let status {
                extraJobs[sourceID] = status
                if let cancel {
                    extraCancels[sourceID] = cancel
                }
                if let quitCancel {
                    extraQuitCancels[sourceID] = quitCancel
                }
            } else {
                extraJobs.removeValue(forKey: sourceID)
                extraCancels.removeValue(forKey: sourceID)
                extraQuitCancels.removeValue(forKey: sourceID)
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

    // MARK: - Quit (ADR-019)

    /// Work quit must not cut off silently: every unfinished runner job plus the
    /// extra sources that block quit. Read under the locks, not from `jobs`,
    /// which a background update publishes one main-queue hop later.
    public var quitBlockingWork: [ShellJobStatus] {
        let runner = jobRunner.snapshot().map(ShellJobStatus.fromJob)
        let extras = lock.withLock {
            extraJobs.keys.sorted().compactMap { extraJobs[$0] }.filter(\.blocksQuit)
        }
        return runner + extras
    }

    /// True until cancelled work has unwound: a runner job reads as cancelled
    /// at once, but its operation (helper teardown, partial-file cleanup) is
    /// still running until the runner reports it finished.
    public var hasUnfinishedQuitBlockingWork: Bool {
        if jobRunner.hasUnfinishedWork { return true }
        return lock.withLock { extraJobs.values.contains(where: \.blocksQuit) }
    }

    /// Confirmed quit: cancel every runner job and every extra source, through
    /// its quit cancel where it registered one (the Vault's jobs-strip cancel
    /// only opens its stop sheet).
    public func cancelAllForQuit() {
        let extras = lock.withLock {
            extraJobs.keys.sorted().compactMap { extraQuitCancels[$0] ?? extraCancels[$0] }
        }
        extras.forEach { $0() }
        for job in jobRunner.snapshot() {
            jobRunner.cancelJob(id: job.id)
        }
    }

    private func applyRunnerSnapshot(_ jobs: [Job]) {
        lock.withLock {
            runnerJobs = jobs.map(ShellJobStatus.fromJob)
        }
        republish()
    }

    /// Publishes the listed rows only; an unlisted registration (a recorder
    /// take) leaves `jobs` unchanged and so re-evaluates no view.
    private func republish() {
        let merged = lock.withLock {
            runnerJobs + extraJobs.keys.sorted().compactMap { extraJobs[$0] }.filter(\.listed)
        }
        if Thread.isMainThread {
            publish(merged)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.publish(merged)
            }
        }
    }

    private func publish(_ merged: [ShellJobStatus]) {
        guard merged != jobs else { return }
        jobs = merged
    }
}
