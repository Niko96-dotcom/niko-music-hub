import AppCore
import Foundation
import NikoMusicCore

struct ProjectVaultQueuedOperation {
    let songID: String
    let projectKey: String
    let songName: String
    let label: String
    let startMessage: String
    let rootIDs: [UUID?]
    let perform: @MainActor (ArchiveBrowserViewModel) async -> Bool
}

extension ArchiveBrowserViewModel {
    private var vaultQueueRootIDs: [UUID?] {
        [projectVaultPresentationContext?.activeRoot?.id, projectVaultPresentationContext?.archiveRoot?.id]
    }

    func projectVaultQueueMessage(for song: Song) -> String? {
        if let position = projectVaultPendingOperations.firstIndex(where: { $0.songID == song.id }) {
            return "Queued: \(projectVaultPendingOperations[position].label) — \(position + 1) ahead."
        }
        if let operation = projectVaultActiveOperation, operation.songID == song.id {
            return "\(operation.label) in progress…"
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
            label: label, startMessage: startMessage, rootIDs: vaultQueueRootIDs, perform: perform
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
        projectVaultQueueTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshProjectVaultPresentationContext()
            let succeeded: Bool
            if operation.rootIDs != self.vaultQueueRootIDs {
                self.setProjectVaultStatusMessage("Queued request cancelled because the Project Vault folders changed.")
                succeeded = false
            } else {
                succeeded = await operation.perform(self)
            }
            self.projectVaultOperationMessages[operation.songID] = self.statusBaseMessage
            if !succeeded { self.projectVaultQueueFailures.append(operation.songName) }
            self.projectVaultBusySongIDs.remove(operation.songID)
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
