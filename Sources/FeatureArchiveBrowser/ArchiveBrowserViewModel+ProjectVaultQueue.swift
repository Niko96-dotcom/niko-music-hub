import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    var vaultQueueRootIDs: [UUID?] {
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
        if pendingArchiveConfirmation?.songID == song.id {
            pendingArchiveConfirmation = nil
        }
        // Single cancellation owner: `cancelQueued` already cancels this
        // song's Done retry budget and capacity postponement.
        vaultOperations.cancelQueued(songID: song.id, songTitle: song.effectiveDisplayTitle)
    }

    public func requestStopActiveProjectVaultTransfer() {
        guard projectVaultActiveOperation != nil else { return }
        pendingStopTransferConfirmation = true
    }

    public func keepActiveProjectVaultTransfer() {
        pendingStopTransferConfirmation = false
    }

    public func confirmStopActiveProjectVaultTransfer() {
        pendingStopTransferConfirmation = false
        vaultOperations.confirmStopActiveTransfer()
    }

    func cancelPendingProjectVaultOperations() {
        cancelBoundArchiveCapture()
        vaultOperations.cancelAllPending()
        pendingArchiveConfirmation = nil
    }

    /// P2 batch-stop truth lives in the single operation owner
    /// (`ProjectVaultOperationCoordinator`); stable songID binding, never titles.

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
        let capturedRootIDs = vaultQueueRootIDs
        let songID = song.id
        let songName = song.effectiveDisplayTitle
        let projectKey = key
        let body = perform
        // Weak capture: the coordinator never retains this view model. The
        // polling tasks below preserve the exact live-phase/restore-progress
        // behavior while the coordinator owns serial dispatch, stop
        // accounting, and footers.
        vaultOperations.enqueue(
            songID: songID,
            projectKey: projectKey,
            songName: songName,
            label: label,
            startMessage: startMessage,
            rootIDs: capturedRootIDs,
            trigger: trigger,
            tracksRestoreProgress: tracksRestoreProgress
        ) { [weak self] in
            guard let self else { return false }
            let progressTask = Task { @MainActor [weak self] in
                guard tracksRestoreProgress, let projectID = UUID(uuidString: projectKey) else { return }
                while !Task.isCancelled {
                    let progress = await self?.projectVaultRuntime?.restoreProgress(for: ProjectID(rawValue: projectID))
                    guard !Task.isCancelled,
                          self?.projectVaultActiveOperation?.projectKey == projectKey else { return }
                    if self?.projectVaultRestoreProgress != progress { self?.projectVaultRestoreProgress = progress }
                    self?.refreshVaultTransferJobStatus(songName: songName, progress: progress)
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
                guard !tracksRestoreProgress else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
                    guard !Task.isCancelled, let self else { return }
                    // Refresh the narrow settings context so root comparisons
                    // use live settings, not a stale capture. This only
                    // re-reads snapshots/cache and rebuilds the presentation
                    // map when values changed; it never enqueues another
                    // automatic generation.
                    self.refreshProjectVaultPresentationContext(notifyWhenChanged: false)
                    guard self.projectVaultActiveOperation?.songID == songID,
                          self.projectVaultActiveOperation?.projectKey == projectKey,
                          capturedRootIDs == self.vaultQueueRootIDs else { return }
                    guard let runtime = self.projectVaultRuntime else { continue }
                    do {
                        let snapshots = try await runtime.snapshots()
                        guard !Task.isCancelled,
                              self.projectVaultActiveOperation?.songID == songID,
                              self.projectVaultActiveOperation?.projectKey == projectKey,
                              capturedRootIDs == self.vaultQueueRootIDs else { return }
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
            return await body(self)
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
