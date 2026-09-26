import AppCore
import Combine
import Foundation

/// Single MainActor owner for Project Vault transfer queue state, running
/// task/stop, per-request batch accounting, and bounded Done-retry bookkeeping.
///
/// `ArchiveBrowserViewModel` keeps confirmations, presentation, snapshots, and
/// status composition; this coordinator owns every mutation of the queue,
/// busy set, operation messages, failures, batch counters, stop flag, running
/// task, retry tasks/attempts, and capacity postponement. The view model
/// forwards read-only access so existing views/tests keep compiling with no UI
/// edits, and delegates every mutation through the intentional operations
/// below. No duplicate stored state lives in the view model.
///
/// Operation execution is `() async -> Bool` with weakly captured callers;
/// the coordinator never takes the whole view model. Vault-specific side
/// effects (presentation refresh, snapshot polling, restore progress, shell
/// jobs, recovery scheduling) are injected as small MainActor callbacks with
/// no-op defaults so the coordinator stays testable without a view model.
@MainActor
final class ProjectVaultOperationCoordinator: ObservableObject {
    // MARK: - Queued operation

    struct QueuedOperation: Identifiable {
        var id: String { songID + "#" + projectKey }
        let songID: String
        let projectKey: String
        let songName: String
        let label: String
        let tracksRestoreProgress: Bool
        let startMessage: String
        let rootIDs: [UUID?]
        let trigger: ProjectVaultArchiveTrigger?
        let perform: @MainActor () async -> Bool
    }

    // MARK: - Owned state (single source of truth)

    /// Observation surface: only pending/active/busy/messages publish for
    /// SwiftUI. Batch counters, failure lists, stop/cancel sets, and capacity
    /// postponement are bookkeeping read via plain stored state (footers flow
    /// through `onStatus`); they need no independent UI invalidations.
    @Published private(set) var pendingOperations: [QueuedOperation] = []
    @Published private(set) var activeOperation: QueuedOperation?
    @Published private(set) var busySongIDs: Set<String> = []
    @Published private(set) var operationMessages: [String: String] = [:]
    private(set) var queueFailures: [String] = []
    private(set) var queueBatchCount = 0
    private(set) var stoppedIDsForBatch: Set<String> = []
    private(set) var canceledIDsForBatch: Set<String> = []
    private(set) var stoppedRequestCountForBatch = 0
    private(set) var canceledRequestCountForBatch = 0
    private(set) var capacityPostponedSongIDs: Set<String> = []

    private(set) var queueTask: Task<Void, Never>?
    private(set) var stopRequested = false
    private(set) var retryTasks: [String: Task<Void, Never>] = [:]
    private(set) var retryAttemptCounts: [String: Int] = [:]
    var doneRetryDelay: Duration = .seconds(60)

    // MARK: - Injected view-model callbacks (all optional for standalone tests)

    /// Publish a vault-owned footer/status message.
    var onStatus: (@MainActor (String?) -> Void)?
    /// Current footer base for post-operation per-song copies.
    var currentStatusBase: (@MainActor () -> String?)?
    /// Fresh root IDs for dispatch-time revalidation.
    var currentRootIDs: (@MainActor () -> [UUID?])?
    /// Refresh the narrow presentation context before dispatch.
    var refreshPresentationForDispatch: (@MainActor () -> Void)?
    /// Mirror active-operation changes into the shell job center.
    var onActiveChanged: (@MainActor () -> Void)?
    var onLogStart: (@MainActor (String) -> Void)?
    var onLogFinish: (@MainActor (String, Bool, Bool) -> Void)?
    /// Drain hook (recovery scheduling) after the last operation finishes.
    var onQueueDrained: (@MainActor () async -> Void)?

    init() {}

    /// `queueTask`/`retryTasks` are Sendable task handles and `Task.cancel()`
    /// is thread-safe, so `deinit` cancels them directly with no
    /// actor-isolated method call. When the owning view model releases this
    /// coordinator, `deinit` cancels any sleeping retry and the running queue
    /// task so no callback fires after the owner is gone. The retry closures
    /// also capture `weak self`, so a released owner performs nothing even if
    /// a sleep already elapsed.
    deinit {
        queueTask?.cancel()
        retryTasks.values.forEach { $0.cancel() }
    }

    // MARK: - Teardown

    /// Cancel running and delayed work without touching per-song messages.
    /// Explicit root-change/cancel-all path where the caller owns messaging.
    /// `deinit` cancels the same Sendable task handles directly.
    func cancelForTeardown() {
        queueTask?.cancel()
        queueTask = nil
        stopRequested = false
        for task in retryTasks.values { task.cancel() }
        retryTasks.removeAll()
        retryAttemptCounts.removeAll()
    }

    // MARK: - Enqueue / serial dispatch

    /// Enqueue one transfer. Duplicate prevention by song AND canonical
    /// project identity matches the frozen contract. Returns false when the
    /// request was a duplicate and nothing was enqueued.
    @discardableResult
    func enqueue(
        songID: String,
        projectKey: String,
        songName: String,
        label: String,
        startMessage: String,
        rootIDs: [UUID?],
        trigger: ProjectVaultArchiveTrigger?,
        tracksRestoreProgress: Bool = false,
        perform: @escaping @MainActor () async -> Bool
    ) -> Bool {
        guard !busySongIDs.contains(songID),
              activeOperation?.projectKey != projectKey,
              !pendingOperations.contains(where: { $0.projectKey == projectKey }) else { return false }
        if activeOperation == nil {
            queueFailures = []
            queueBatchCount = 0
            stoppedIDsForBatch = []
            canceledIDsForBatch = []
            stoppedRequestCountForBatch = 0
            canceledRequestCountForBatch = 0
        }
        queueBatchCount += 1
        busySongIDs.insert(songID)
        operationMessages.removeValue(forKey: songID)
        pendingOperations.append(QueuedOperation(
            songID: songID, projectKey: projectKey, songName: songName,
            label: label, tracksRestoreProgress: tracksRestoreProgress,
            startMessage: startMessage, rootIDs: rootIDs, trigger: trigger,
            perform: perform
        ))
        if activeOperation == nil {
            startNext()
        } else {
            onStatus?("Queued \(label.lowercased()) for \(songName). \(pendingOperations.count) waiting.")
        }
        return true
    }

    private func startNext() {
        guard activeOperation == nil, !pendingOperations.isEmpty else { return }
        let operation = pendingOperations.removeFirst()
        activeOperation = operation
        onStatus?(operation.startMessage)
        onLogStart?(operation.label)
        onActiveChanged?()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.run(operation)
        }
        queueTask = task
    }

    private func run(_ operation: QueuedOperation) async {
        refreshPresentationForDispatch?()
        let succeeded: Bool
        if let currentRootIDs, operation.rootIDs != currentRootIDs() {
            onStatus?("Queued request cancelled because the Project Vault folders changed.")
            succeeded = false
        } else {
            succeeded = await operation.perform()
        }
        let wasStopped = Task.isCancelled || stopRequested
        if wasStopped {
            stoppedIDsForBatch.insert(operation.songID)
            stoppedRequestCountForBatch += 1
            operationMessages[operation.songID] = CancelCopy.transferStopped
            onStatus?(CancelCopy.transferStopped)
            stopRequested = false
            if succeeded {
                queueFailures.append(operation.songName)
            }
        } else {
            // Dictionary optional-assignment semantics preserved: a nil base
            // removes the per-song entry, matching the pre-extraction runner.
            operationMessages[operation.songID] = currentStatusBase?() ?? nil
        }
        onLogFinish?(operation.label, succeeded, wasStopped)
        if !succeeded { queueFailures.append(operation.songName) }
        busySongIDs.remove(operation.songID)
        activeOperation = nil
        queueTask = nil
        onActiveChanged?()
        if !pendingOperations.isEmpty {
            startNext()
        } else {
            publishBatchFooter()
            await onQueueDrained?()
        }
    }

    private func publishBatchFooter() {
        let stoppedCount = stoppedRequestCountForBatch
        let canceledCount = canceledRequestCountForBatch
        if stoppedCount > 0, queueBatchCount > 1 {
            let total = queueBatchCount
            let completed = max(0, total - queueFailures.count - canceledCount)
            var footer: String
            if canceledCount == 0 {
                footer = "\(CancelCopy.transferStopped) Project Vault queue stopped: \(completed) completed, \(stoppedCount) stopped of \(total)."
            } else {
                footer = "\(CancelCopy.transferStopped) Project Vault queue stopped: \(completed) completed, \(stoppedCount) stopped, \(canceledCount) cancelled of \(total)."
            }
            if !queueFailures.isEmpty {
                footer += " Needs attention: \(queueFailures.joined(separator: ", "))."
            }
            onStatus?(footer)
        } else if canceledCount > 0, queueBatchCount > 1 {
            let total = queueBatchCount
            let completed = max(0, total - queueFailures.count - canceledCount)
            var footer = "Project Vault queue finished: \(completed) completed, \(canceledCount) cancelled of \(total)."
            if !queueFailures.isEmpty {
                footer += " Needs attention: \(queueFailures.joined(separator: ", "))."
            }
            onStatus?(footer)
        } else if queueBatchCount > 1 {
            onStatus?(queueFailures.isEmpty
                ? "Project Vault queue finished."
                : "Project Vault queue finished. Needs attention: \(queueFailures.joined(separator: ", ")).")
        }
    }

    // MARK: - Cancel / stop

    /// Cancel a queued (not yet active) song. When the song also owns the
    /// active operation the queued duplicates are dropped but the transfer
    /// continues; otherwise the song is unmarked busy with truthful
    /// per-request accounting.
    func cancelQueued(songID: String, songTitle: String) {
        cancelDoneRetry(for: songID)
        guard pendingOperations.contains(where: { $0.songID == songID }) else { return }
        let removedRequestCount = pendingOperations.filter { $0.songID == songID }.count
        let activeOwnsSong = activeOperation?.songID == songID
        pendingOperations.removeAll(where: { $0.songID == songID })
        if activeOwnsSong {
            onStatus?("Queued request cancelled for \(songTitle). Transfer continues.")
            return
        }
        canceledIDsForBatch.insert(songID)
        canceledRequestCountForBatch += max(1, removedRequestCount)
        busySongIDs.remove(songID)
        operationMessages[songID] = "Queued request cancelled. No project files were changed."
        onStatus?("Queued request cancelled for \(songTitle).")
    }

    /// Cancel every pending request. The active transfer keeps running; each
    /// pending request counts once toward the batch-cancelled total.
    func cancelAllPending() {
        for task in retryTasks.values { task.cancel() }
        retryTasks.removeAll()
        retryAttemptCounts.removeAll()
        capacityPostponedSongIDs.removeAll()
        for operation in pendingOperations {
            busySongIDs.remove(operation.songID)
            operationMessages[operation.songID] = "Queued request cancelled. No project files were changed."
            canceledIDsForBatch.insert(operation.songID)
            canceledRequestCountForBatch += 1
        }
        pendingOperations.removeAll()
    }

    func clearAllOperationMessages() {
        operationMessages.removeAll()
    }

    func removeOperationMessage(forKey key: String) {
        operationMessages.removeValue(forKey: key)
    }

    /// Stop request from the active-transfer confirmation. The runner records
    /// truthful stopped accounting when the task observes cancellation.
    func confirmStopActiveTransfer() {
        guard activeOperation != nil else { return }
        stopRequested = true
        queueTask?.cancel()
    }

    // MARK: - Done revoke (Undo / status away from Done)

    /// Revoke Done-bound work for one song. Cancels the retry budget, removes
    /// matching queued Done operations, and stops the inflight Done task where
    /// possible. Other songs are untouched. Manual (non-Done) requests for the
    /// same song are preserved.
    func revokeDoneWork(songID: String) {
        var removedPending = false
        var removedRequestCount = 0
        while let index = pendingOperations.firstIndex(where: {
            $0.songID == songID && $0.trigger == .workflowDone
        }) {
            pendingOperations.remove(at: index)
            removedPending = true
            removedRequestCount += 1
        }
        cancelDoneRetry(for: songID)
        if let active = activeOperation,
           active.songID == songID, active.trigger == .workflowDone {
            stopRequested = true
            queueTask?.cancel()
        } else if removedPending,
                  activeOperation?.songID != songID,
                  !pendingOperations.contains(where: { $0.songID == songID }) {
            canceledIDsForBatch.insert(songID)
            canceledRequestCountForBatch += max(1, removedRequestCount)
            busySongIDs.remove(songID)
            operationMessages[songID] = "Queued request cancelled. No project files were changed."
            onStatus?("Undo revoked the Done archive before it ran. No project files were changed.")
        }
    }

    // MARK: - Bounded Done retry + capacity postponement

    /// Cancel a delayed retry without reusing its approval and release any
    /// capacity postponement. Used for cancel/revoke paths where a fresh
    /// explicit Done must resume normal automatic behavior.
    func cancelDoneRetry(for songID: String) {
        retryTasks.removeValue(forKey: songID)?.cancel()
        retryAttemptCounts.removeValue(forKey: songID)
        capacityPostponedSongIDs.remove(songID)
    }

    /// Cancel only the delayed retry budget (explicit confirmations restart
    /// the budget and supersede a waiting timer without touching capacity).
    func cancelPendingRetry(for songID: String) {
        retryTasks.removeValue(forKey: songID)?.cancel()
        retryAttemptCounts.removeValue(forKey: songID)
    }

    /// Record a successful transfer: the retry budget and any capacity
    /// postponement are released.
    func noteSuccessfulTransfer(for songID: String) {
        retryTasks.removeValue(forKey: songID)?.cancel()
        retryAttemptCounts.removeValue(forKey: songID)
        capacityPostponedSongIDs.remove(songID)
    }

    func noteCapacityPostponed(songID: String) {
        capacityPostponedSongIDs.insert(songID)
    }

    func releaseCapacityPostponement(for songID: String) {
        capacityPostponedSongIDs.remove(songID)
    }

    func isCapacityPostponed(songID: String) -> Bool {
        capacityPostponedSongIDs.contains(songID)
    }

    var isIdle: Bool { busySongIDs.isEmpty }

    /// Schedule a bounded Done retry. At most 3 attempts per song; the caller
    /// supplies the already-downgraded copy-only re-enqueue action. Returns
    /// false when a retry is already waiting or the budget is exhausted.
    @discardableResult
    func scheduleRetry(
        for songID: String,
        action: @escaping @MainActor () -> Void
    ) -> Bool {
        let attemptCount = retryAttemptCounts[songID, default: 0]
        guard retryTasks[songID] == nil, attemptCount < 3 else { return false }
        retryAttemptCounts[songID] = attemptCount + 1
        let delay = doneRetryDelay
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.retryTasks.removeValue(forKey: songID)
            action()
        }
        retryTasks[songID] = task
        return true
    }
}
