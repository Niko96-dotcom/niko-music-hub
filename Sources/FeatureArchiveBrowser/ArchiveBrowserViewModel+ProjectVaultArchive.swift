import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func requestArchiveNow(for song: Song) {
        guard canArchiveInProjectVault(song) else { return }
        let settings = (try? settingsStore.loadSettings())?.vault
        pendingArchiveConfirmation = ProjectVaultArchiveConfirmation(
            songID: song.id,
            songTitle: song.effectiveDisplayTitle,
            trigger: .manual,
            willRemoveActiveCopy: true, // Archive Now always uses .manual → reuseTerminal
            independentBackupConfirmed: settings?.independentBackupConfirmed ?? false
        )
    }

    func requestWorkflowDoneArchive(for song: Song) {
        guard canMutateWorkflowStatus(for: song), song.workflowStatus != .done else { return }
        guard canArchiveInProjectVault(song) else {
            applyWorkflowStatus(.done, for: song)
            return
        }
        let settings = (try? settingsStore.loadSettings())?.vault
        pendingArchiveConfirmation = ProjectVaultArchiveConfirmation(
            songID: song.id,
            songTitle: song.effectiveDisplayTitle,
            trigger: .workflowDone,
            willRemoveActiveCopy: settings.map(ProjectVaultRolloutPolicy.permitsActiveCopyRemoval) ?? false,
            independentBackupConfirmed: settings?.independentBackupConfirmed ?? false
        )
    }

    func confirmPendingArchive() {
        guard let pending = pendingArchiveConfirmation,
              let song = songs.first(where: { $0.id == pending.songID }) else { return }
        pendingArchiveConfirmation = nil
        // An explicit user confirmation restarts the bounded Done-retry budget and
        // supersedes any timer-driven retry that is still waiting for this song.
        projectVaultRetryTasks.removeValue(forKey: song.id)?.cancel()
        projectVaultRetryAttemptCounts.removeValue(forKey: song.id)
        if pending.trigger == .workflowDone {
            let previous = song.workflowStatus
            if song.workflowStatus != .done {
                commitWorkflowStatus(.done, for: song)
            }
            registerWorkflowStatusUndo(
                songID: song.id,
                previousStatus: previous,
                actionName: "Mark Done"
            )
            let updated = songs.first(where: { $0.id == song.id }) ?? song
            archiveInProjectVault(updated, trigger: .workflowDone)
            return
        }
        archiveInProjectVault(song, trigger: pending.trigger)
    }

    func cancelPendingArchive() {
        pendingArchiveConfirmation = nil
    }

    func archiveInProjectVault(_ song: Song, trigger: ProjectVaultArchiveTrigger = .manual) {
        guard let projectVaultRuntime,
              canArchiveInProjectVault(song),
              !projectVaultBusySongIDs.contains(song.id) else { return }
        enqueueProjectVaultOperation(
            for: song, label: trigger == .backupCopy ? "Backup" : "Archive",
            startMessage: trigger == .workflowDone ? "Done — checking Project Vault safety…" : "Archiving and verifying a Project Vault copy…",
            trigger: trigger
        ) { model in
            do {
                let currentSong = model.songs.first { $0.id == song.id } ?? song
                let snapshot = try await model.waitForProjectVaultSlot {
                    try await projectVaultRuntime.archive(song: currentSong, trigger: trigger)
                }
                model.projectVaultRetryTasks.removeValue(forKey: song.id)?.cancel()
                model.projectVaultRetryAttemptCounts.removeValue(forKey: song.id)
                model.cacheProjectVaultSnapshot(snapshot)
                model.rebuildProjectVaultPresentationCache()
                await model.refreshProjectVaultSnapshots()
                let activeRetained = FileManager.default.fileExists(atPath: song.folderPath.path)
                model.setProjectVaultStatusMessage(activeRetained
                    ? "Backup copy verified. The project remains in Active Projects."
                    : "Archived and verified. Find this song in Show archived projects to restore it.")
                return true
            } catch is CancellationError {
                _ = await model.refreshProjectVaultSnapshots()
                model.setProjectVaultStatusMessage(CancelCopy.transferStopped)
                return false
            } catch is VaultTransferInterruption {
                _ = await model.refreshProjectVaultSnapshots()
                model.setProjectVaultStatusMessage(CancelCopy.transferStopped)
                return false
            } catch let error as ProjectVaultRuntimeError {
                if case .identityAmbiguous(let title, let reason) = error {
                    await model.beginIdentityReview(
                        for: model.songs.first { $0.id == song.id } ?? song,
                        title: title,
                        reason: reason,
                        trigger: trigger
                    )
                    return false
                }
                _ = await model.refreshProjectVaultSnapshots()
                if trigger == .workflowDone {
                    model.setProjectVaultStatusMessage("Marked Done. \(error.localizedDescription)")
                    model.diagnostics.log(.warning, "Done auto-archive postponed: \(error)")
                    if case .activityPostponed(let reason) = error,
                       reason.permitsBoundedAutomaticRetry {
                        model.scheduleDoneArchiveRetry(for: song)
                    }
                    return false
                }
                model.setProjectVaultStatusMessage("Archive did not complete: \(error.localizedDescription)")
                model.diagnostics.log(.error, "Project Vault archive failed: \(error)")
                return false
            } catch {
                _ = await model.refreshProjectVaultSnapshots()
                model.setProjectVaultStatusMessage("Archive did not complete: \(error.localizedDescription)")
                model.diagnostics.log(.error, "Project Vault archive failed: \(error)")
                return false
            }
        }
    }

    private func scheduleDoneArchiveRetry(for song: Song) {
        let attemptCount = projectVaultRetryAttemptCounts[song.id, default: 0]
        guard projectVaultRetryTasks[song.id] == nil, attemptCount < 3 else { return }
        projectVaultRetryAttemptCounts[song.id] = attemptCount + 1
        projectVaultRetryTasks[song.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled else { return }
            self.projectVaultRetryTasks.removeValue(forKey: song.id)
            guard let current = self.songs.first(where: { $0.id == song.id }),
                  current.workflowStatus == .done else { return }
            self.archiveInProjectVault(current, trigger: .workflowDone)
        }
    }
}
