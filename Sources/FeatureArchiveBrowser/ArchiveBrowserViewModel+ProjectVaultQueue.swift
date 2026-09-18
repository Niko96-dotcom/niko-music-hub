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
            messages[operation.songID] = projectVaultRestoreProgress?.title ?? operation.startMessage
        }
        return messages
    }

    func projectVaultQueueMessage(for song: Song) -> String? {
        if let position = projectVaultPendingOperations.firstIndex(where: { $0.songID == song.id }) {
            return "Queued: \(projectVaultPendingOperations[position].label) — \(position + 1) ahead."
        }
        if let operation = projectVaultActiveOperation, operation.songID == song.id {
            return projectVaultRestoreProgress?.title ?? operation.startMessage
        }
        return projectVaultOperationMessages[song.id]
    }

    func cancelQueuedProjectVaultOperation(for song: Song) {
        guard let index = projectVaultPendingOperations.firstIndex(where: { $0.songID == song.id }) else { return }
        projectVaultPendingOperations.remove(at: index)
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
        for operation in projectVaultPendingOperations {
            projectVaultBusySongIDs.remove(operation.songID)
        }
        projectVaultPendingOperations.removeAll()
    }

    func enqueueProjectVaultOperation(
        for song: Song,
        label: String,
        startMessage: String,
        tracksRestoreProgress: Bool = false,
        trigger: ProjectVaultArchiveTrigger? = nil,
        perform: @escaping @MainActor (ArchiveBrowserViewModel) async -> Bool
    ) {
        let key = projectVaultSnapshot(for: song)?.record.id.description
            ?? song.folderPath.standardizedFileURL.resolvingSymlinksInPath().path
        guard !projectVaultBusySongIDs.contains(song.id),
              projectVaultActiveOperation?.projectKey != key,
              !projectVaultPendingOperations.contains(where: { $0.projectKey == key }) else { return }
        if projectVaultActiveOperation == nil {
            projectVaultQueueFailures = []
            projectVaultQueueBatchCount = 0
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
            defer { progressTask.cancel(); self.projectVaultRestoreProgress = nil }

            self.refreshProjectVaultPresentationContext()
            let succeeded: Bool
            if operation.rootIDs != self.vaultQueueRootIDs {
                self.setProjectVaultStatusMessage("Queued request cancelled because the Project Vault folders changed.")
                succeeded = false
            } else {
                succeeded = await operation.perform(self)
            }
            if Task.isCancelled || self.projectVaultStopRequested {
                self.projectVaultOperationMessages[operation.songID] = CancelCopy.transferStopped
                self.setProjectVaultStatusMessage(CancelCopy.transferStopped)
                self.projectVaultStopRequested = false
            }
            self.projectVaultOperationMessages[operation.songID] = self.statusBaseMessage
            self.diagnostics.scoped(to: .vault).log(succeeded ? .info : .error, "Vault operation finished (label=\(operation.label), succeeded=\(succeeded))")
            if !succeeded { self.projectVaultQueueFailures.append(operation.songName) }
            self.projectVaultBusySongIDs.remove(operation.songID)
            progressTask.cancel()
            self.projectVaultRestoreProgress = nil
            self.projectVaultActiveOperation = nil
            self.projectVaultQueueTask = nil
            if !self.projectVaultPendingOperations.isEmpty {
                self.startNextProjectVaultOperation()
            } else {
                if self.projectVaultQueueBatchCount > 1 {
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
