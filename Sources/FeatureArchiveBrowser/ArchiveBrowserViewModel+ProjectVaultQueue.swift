import AppCore
import Foundation
import NikoMusicCore

struct ProjectVaultQueuedOperation {
    let songID: String
    let projectKey: String
    let songName: String
    let label: String
    let tracksRestoreProgress: Bool
    let startMessage: String
    let rootIDs: [UUID?]
    let trigger: ProjectVaultArchiveTrigger?
    let perform: @MainActor (ArchiveBrowserViewModel) async -> Bool
}

extension ArchiveBrowserViewModel {
    private var vaultQueueRootIDs: [UUID?] {
        [projectVaultPresentationContext?.activeRoot?.id, projectVaultPresentationContext?.archiveRoot?.id]
    }

    var projectVaultActivityMessages: [String: String] {
        var messages: [String: String] = [:]
        for (index, operation) in projectVaultPendingOperations.enumerated() {
            messages[operation.songID] = "Queued · \(index + 1) ahead"
        }
        if let operation = projectVaultActiveOperation {
            messages[operation.songID] = projectVaultRestoreProgress?.title
                ?? projectVaultLiveArchivePhaseMessage(for: operation.songID)
                ?? operation.startMessage
        }
        return messages
    }

    func projectVaultQueueMessage(for song: Song) -> String? {
        if let position = projectVaultPendingOperations.firstIndex(where: { $0.songID == song.id }) {
            return "Queued: \(projectVaultPendingOperations[position].label) — \(position + 1) ahead."
        }
        if let operation = projectVaultActiveOperation, operation.songID == song.id {
            return projectVaultRestoreProgress?.title
                ?? projectVaultLiveArchivePhaseMessage(for: song.id)
                ?? operation.startMessage
        }
        let message = projectVaultOperationMessages[song.id]
        if message == ProjectVaultActivityExplanation.transfer(.awaitingProviderDurability),
           projectVaultSnapshot(for: song)?.transfer?.isWaitingForProviderUpload != true {
            return nil // The current presentation owns the result of background recovery.
        }
        return message
    }

    /// Live archive phase for the active queue entry, derived from the
    /// already-persisted transfer snapshot. Returns the current
    /// `transferStatusLabel` once the engine has persisted phase evidence, so
    /// the card/detail message names the actual phase
    /// (Queued/Copying/Verifying/Waiting for upload) instead of the static
    /// start message. Nil without evidence: callers keep the start message,
    /// restore operations keep their progress title, and post-operation
    /// failure text is never rewritten here.
    private func projectVaultLiveArchivePhaseMessage(for songID: String) -> String? {
        guard let operation = projectVaultActiveOperation,
              operation.songID == songID,
              !operation.tracksRestoreProgress,
              let song = songs.first(where: { $0.id == songID }),
              let state = projectVaultSnapshot(for: song)?.transfer?.state else { return nil }
        return ProjectVaultCardPresentation.transferStatusLabel(state)
    }

    func cancelQueuedProjectVaultOperation(for song: Song) {
        cancelBoundArchiveCapture(for: song.id)
        cancelDoneArchiveRetry(for: song.id)
        if pendingArchiveConfirmation?.songID == song.id {
            pendingArchiveConfirmation = nil
        }
        guard projectVaultPendingOperations.contains(where: { $0.songID == song.id }) else { return }
        let removedRequestCount = projectVaultPendingOperations.filter { $0.songID == song.id }.count
        let activeOwnsSong = projectVaultActiveOperation?.songID == song.id
        projectVaultPendingOperations.removeAll(where: { $0.songID == song.id })
        if activeOwnsSong {
            setProjectVaultStatusMessage("Queued request cancelled for \(song.effectiveDisplayTitle). Transfer continues.")
            return
        }
        // P2 truthful counts: a queued operation cancelled before execution never
        // completed. Record it per-instance by stable songID so the final footer
        // cannot count it as completed via total-minus-failures.
        // REQUEST-69: also count REQUESTS, not distinct songs: cancel B, requeue
        // B, cancel B is two cancelled requests for one songID.
        var canceledForBatch = vaultQueueCanceledIDsForBatch
        canceledForBatch.insert(song.id)
        vaultQueueCanceledIDsForBatch = canceledForBatch
        vaultQueueCanceledRequestCountForBatch += max(1, removedRequestCount)
        projectVaultBusySongIDs.remove(song.id)
        projectVaultOperationMessages[song.id] = "Queued request cancelled. No project files were changed."
        setProjectVaultStatusMessage("Queued request cancelled for \(song.effectiveDisplayTitle).")
    }

    public var hasActiveProjectVaultTransfer: Bool { projectVaultActiveOperation != nil }

    public func requestStopActiveProjectVaultTransfer() {
        guard projectVaultActiveOperation != nil else { return }
        pendingStopTransferConfirmation = true
    }

    public func keepActiveProjectVaultTransfer() {
        pendingStopTransferConfirmation = false
    }

    public func confirmStopActiveProjectVaultTransfer() {
        pendingStopTransferConfirmation = false
        guard projectVaultActiveOperation != nil else { return }
        projectVaultStopRequested = true
        projectVaultQueueTask?.cancel()
    }

    func cancelPendingProjectVaultOperations() {
        cancelBoundArchiveCapture()
        for (_, task) in projectVaultRetryTasks {
            task.cancel()
        }
        projectVaultRetryTasks.removeAll()
        projectVaultRetryAttemptCounts.removeAll()
        projectVaultCapacityPostponedSongIDs.removeAll()
        pendingArchiveConfirmation = nil
        for operation in projectVaultPendingOperations {
            projectVaultBusySongIDs.remove(operation.songID)
            projectVaultOperationMessages[operation.songID] = "Queued request cancelled. No project files were changed."
            var canceledForBatch = vaultQueueCanceledIDsForBatch
            canceledForBatch.insert(operation.songID)
            vaultQueueCanceledIDsForBatch = canceledForBatch
            // REQUEST-69: one REQUEST per pending operation, even when two
            // operations share a songID across requeues.
            vaultQueueCanceledRequestCountForBatch += 1
        }
        projectVaultPendingOperations.removeAll()
    }

    /// P2 batch-stop truth lives as per-instance storage
    /// (`vaultQueueStoppedIDsForBatch` in `ArchiveBrowserViewModel.swift`),
    /// reset with each batch. Stable songID binding, never titles.

    func enqueueProjectVaultOperation(
        for song: Song,
        label: String,
        startMessage: String,
        tracksRestoreProgress: Bool = false,
        trigger: ProjectVaultArchiveTrigger? = nil,
        perform: @escaping @MainActor (ArchiveBrowserViewModel) async -> Bool
    ) {
        // Refresh the narrow settings context so the captured rootIDs match
        // live settings. A stale capture (e.g. from init before songs were
        // assigned) would otherwise abort the poll/dispatch below even though
        // the live roots are correct. This only rebuilds the card map; it
        // never enqueues.
        refreshProjectVaultPresentationContext(notifyWhenChanged: false)
        let key = projectVaultSnapshot(for: song)?.record.id.description
            ?? song.folderPath.standardizedFileURL.resolvingSymlinksInPath().path
        guard !projectVaultBusySongIDs.contains(song.id),
              projectVaultActiveOperation?.projectKey != key,
              !projectVaultPendingOperations.contains(where: { $0.projectKey == key }) else { return }
        if projectVaultActiveOperation == nil {
            projectVaultQueueFailures = []
            projectVaultQueueBatchCount = 0
            vaultQueueStoppedIDsForBatch = []
            vaultQueueCanceledIDsForBatch = []
            vaultQueueStoppedRequestCountForBatch = 0
            vaultQueueCanceledRequestCountForBatch = 0
        }
        projectVaultQueueBatchCount += 1
        projectVaultBusySongIDs.insert(song.id)
        projectVaultOperationMessages.removeValue(forKey: song.id)
        projectVaultPendingOperations.append(ProjectVaultQueuedOperation(
            songID: song.id, projectKey: key, songName: song.effectiveDisplayTitle,
            label: label, tracksRestoreProgress: tracksRestoreProgress, startMessage: startMessage, rootIDs: vaultQueueRootIDs, trigger: trigger, perform: perform
        ))
        if projectVaultActiveOperation == nil {
            startNextProjectVaultOperation()
        } else {
            setProjectVaultStatusMessage("Queued \(label.lowercased()) for \(song.effectiveDisplayTitle). \(projectVaultPendingOperations.count) waiting.")
        }
    }

    private func startNextProjectVaultOperation() {
        guard projectVaultActiveOperation == nil, !projectVaultPendingOperations.isEmpty else { return }
        let operation = projectVaultPendingOperations.removeFirst()
        projectVaultActiveOperation = operation
        setProjectVaultStatusMessage(operation.startMessage)
        // High-signal vault boundary: label is a fixed string (public); song
        // names/paths are never logged.
        self.diagnostics.scoped(to: .vault).log(.info, "Vault operation started (label=\(operation.label))")
        projectVaultQueueTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let progressTask = Task { @MainActor [weak self] in
                guard operation.tracksRestoreProgress, let projectID = UUID(uuidString: operation.projectKey) else { return }
                while !Task.isCancelled {
                    let progress = await self?.projectVaultRuntime?.restoreProgress(for: ProjectID(rawValue: projectID))
                    guard !Task.isCancelled,
                          self?.projectVaultActiveOperation?.projectKey == operation.projectKey else { return }
                    if self?.projectVaultRestoreProgress != progress { self?.projectVaultRestoreProgress = progress }
                    self?.refreshVaultTransferJobStatus(songName: operation.songName, progress: progress)
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                }
            }
            // Live archive phases: the engine persists each phase while
            // `perform` blocks, so refresh the already-persisted snapshots on
            // a bounded 750 ms cadence for non-restore operations. Restore
            // keeps its own progress poll above. This task only re-reads
            // snapshots/cache and rebuilds the presentation map when values
            // actually changed, so queued positions, failure text, and page
            // geometry stay stable. A lookup failure is never a transfer
            // failure: the tick is skipped and the last known phases are kept.
            // The task is bound to this operation's identity and roots and is
            // cancelled at the operation boundary below.
            let archivePhaseTask = Task { @MainActor [weak self] in
                guard !operation.tracksRestoreProgress else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
                    guard !Task.isCancelled, let self else { return }
                    // Refresh the narrow settings context so root comparisons
                    // use live settings, not a stale capture. This only
                    // re-reads snapshots/cache and rebuilds the presentation
                    // map when values changed; it never enqueues another
                    // automatic generation.
                    self.refreshProjectVaultPresentationContext(notifyWhenChanged: false)
                    guard self.projectVaultActiveOperation?.songID == operation.songID,
                          self.projectVaultActiveOperation?.projectKey == operation.projectKey,
                          operation.rootIDs == self.vaultQueueRootIDs else { return }
                    guard let runtime = self.projectVaultRuntime else { continue }
                    do {
                        let snapshots = try await runtime.snapshots()
                        guard !Task.isCancelled,
                              self.projectVaultActiveOperation?.songID == operation.songID,
                              self.projectVaultActiveOperation?.projectKey == operation.projectKey,
                              operation.rootIDs == self.vaultQueueRootIDs else { return }
                        guard snapshots != self.projectVaultSnapshots else { continue }
                        self.projectVaultSnapshots = snapshots
                        self.projectVaultSnapshotsByPath.removeAll()
                        snapshots.forEach(self.cacheProjectVaultSnapshot)
                        self.rebuildProjectVaultPresentationCache()
                    } catch {
                        continue
                    }
                }
            }
            defer { progressTask.cancel(); archivePhaseTask.cancel(); self.projectVaultRestoreProgress = nil }

            self.refreshProjectVaultPresentationContext()
            let succeeded: Bool
            if operation.rootIDs != self.vaultQueueRootIDs {
                self.setProjectVaultStatusMessage("Queued request cancelled because the Project Vault folders changed.")
                succeeded = false
            } else {
                succeeded = await operation.perform(self)
            }
            // P2: a stopped destructive operation must keep its truthful
            // stopped/recovery copy per-song and globally. Never overwrite the
            // per-song recovery message with a later generic footer, and never
            // finish a multi-item batch with an unqualified "queue finished"
            // when an interruption occurred. Normal successful batches keep the
            // exact "Project Vault queue finished." footer.
            let wasStopped = Task.isCancelled || self.projectVaultStopRequested
            if wasStopped {
                var stopped = self.vaultQueueStoppedIDsForBatch
                stopped.insert(operation.songID)
                self.vaultQueueStoppedIDsForBatch = stopped
                // REQUEST-69: count stopped REQUESTS; the same song stopped
                // twice is two stopped requests for one songID.
                self.vaultQueueStoppedRequestCountForBatch += 1
                self.projectVaultOperationMessages[operation.songID] = CancelCopy.transferStopped
                self.setProjectVaultStatusMessage(CancelCopy.transferStopped)
                self.projectVaultStopRequested = false
                // A stop that returned success still did not complete: count it
                // as not-completed so completed/cancelled counts stay accurate.
                if succeeded {
                    self.projectVaultQueueFailures.append(operation.songName)
                }
            } else {
                self.projectVaultOperationMessages[operation.songID] = self.statusBaseMessage
            }
            self.diagnostics.scoped(to: .vault).log(succeeded && !wasStopped ? .info : .error, "Vault operation finished (label=\(operation.label), succeeded=\(succeeded), stopped=\(wasStopped))")
            if !succeeded { self.projectVaultQueueFailures.append(operation.songName) }
            self.projectVaultBusySongIDs.remove(operation.songID)
            progressTask.cancel()
            archivePhaseTask.cancel()
            self.projectVaultRestoreProgress = nil
            self.projectVaultActiveOperation = nil
            self.projectVaultQueueTask = nil
            if !self.projectVaultPendingOperations.isEmpty {
                self.startNextProjectVaultOperation()
            } else {
                // REQUEST-69: footers count REQUESTS. The ID sets collapse
                // repeats (same song cancelled/stopped twice) while the batch
                // total counts every enqueue, so Set.count would under-report
                // and inflate completed via total-minus-failures.
                // (Sets in ArchiveBrowserViewModel.swift stay as stable
                // per-song truth; counts here are the footer source.)
                let stoppedCount = self.vaultQueueStoppedRequestCountForBatch
                let canceledCount = self.vaultQueueCanceledRequestCountForBatch
                if stoppedCount > 0, self.projectVaultQueueBatchCount > 1 {
                    let total = self.projectVaultQueueBatchCount
                    // Truthful completed: total minus failures minus queued
                    // cancellations. A cancelled queued operation never executed,
                    // so it must not be counted as completed.
                    let completed = max(0, total - self.projectVaultQueueFailures.count - canceledCount)
                    var footer: String
                    if canceledCount == 0 {
                        footer = "\(CancelCopy.transferStopped) Project Vault queue stopped: \(completed) completed, \(stoppedCount) stopped of \(total)."
                    } else {
                        footer = "\(CancelCopy.transferStopped) Project Vault queue stopped: \(completed) completed, \(stoppedCount) stopped, \(canceledCount) cancelled of \(total)."
                    }
                    if !self.projectVaultQueueFailures.isEmpty {
                        footer += " Needs attention: \(self.projectVaultQueueFailures.joined(separator: ", "))."
                    }
                    self.setProjectVaultStatusMessage(footer)
                } else if canceledCount > 0, self.projectVaultQueueBatchCount > 1 {
                    // A batch with queued cancellations but no stop must never
                    // report an unqualified "queue finished": cancelled items did
                    // not complete.
                    let total = self.projectVaultQueueBatchCount
                    let completed = max(0, total - self.projectVaultQueueFailures.count - canceledCount)
                    var footer = "Project Vault queue finished: \(completed) completed, \(canceledCount) cancelled of \(total)."
                    if !self.projectVaultQueueFailures.isEmpty {
                        footer += " Needs attention: \(self.projectVaultQueueFailures.joined(separator: ", "))."
                    }
                    self.setProjectVaultStatusMessage(footer)
                } else if self.projectVaultQueueBatchCount > 1 {
                    self.setProjectVaultStatusMessage(self.projectVaultQueueFailures.isEmpty
                        ? "Project Vault queue finished."
                        : "Project Vault queue finished. Needs attention: \(self.projectVaultQueueFailures.joined(separator: ", ")).")
                }
                await self.scheduleProjectVaultRecovery()
            }
        }
    }

    /// NMH-054: mirror the honest restore fraction into the NMH-011 shell jobs
    /// row so progress stays visible after the restore sheet dismisses.
    /// Called from the 500 ms restore-progress poll; the operation-start publish
    /// in `publishShellJobStatus()` still owns the indeterminate initial row.
    private func refreshVaultTransferJobStatus(songName: String, progress: ProjectVaultRestoreProgress?) {
        guard projectVaultActiveOperation != nil else { return }
        jobStatusCenter.setExtraJob(
            sourceID: ShellJobExtraSourceID.vaultTransfer,
            status: ShellJobStatusCopy.vaultTransferStatus(songName: songName, progress: progress),
            cancel: { [weak self] in
                Task { @MainActor in
                    self?.requestStopActiveProjectVaultTransfer()
                }
            }
        )
    }

    /// Background recovery or another app instance can own the runtime lease.
    /// Wait only for admission; never retry an operation that already started.
    func waitForProjectVaultSlot<Value: Sendable>(
        _ operation: () async throws -> Value
    ) async throws -> Value {
        let rootIDs = projectVaultActiveOperation?.rootIDs
        while true {
            try Task.checkCancellation()
            refreshProjectVaultPresentationContext()
            guard rootIDs == vaultQueueRootIDs else { throw CancellationError() }
            do {
                return try await operation()
            } catch ProjectVaultRuntimeError.mutationInProgress {
                setProjectVaultStatusMessage("Waiting for the current Project Vault operation to finish…")
                try await Task.sleep(for: .seconds(1))
            }
        }
    }
}
