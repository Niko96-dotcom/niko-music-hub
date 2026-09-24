import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func confirmProjectVaultRestore(selectedPath: String? = nil, destinationRelativePath: String? = nil) {
        guard let request = projectVaultRestoreRequest else { return }
        let destination = destinationRelativePath ?? request.options.destinationRelativePath
        guard request.options.destinationIssue(for: destination) == nil,
              selectedPath == nil || request.options.versions.contains(where: { $0.relativePath == selectedPath }) else { return }
        projectVaultRestoreRequest = nil
        enqueueProjectVaultRestore(request.song, selectedPath: selectedPath, destinationRelativePath: destination)
    }

    func retryReviewedProjectVaultRestore(for song: Song) {
        guard let runtime = projectVaultRuntime,
              let restoreID = projectVaultPresentation(for: song)?.retryRestoreID else {
            setProjectVaultStatusMessage(
                "Restore retry is unavailable because no preserved Project Vault restore was found."
            )
            return
        }
        guard !projectVaultBusySongIDs.contains(song.id) else { return }
        enqueueProjectVaultOperation(for: song, label: "Retry restore", startMessage: "Retrying this preserved Project Vault restore…", tracksRestoreProgress: true) { model in
            do {
                let completed = try await model.waitForProjectVaultSlot {
                    try await runtime.retryRestore(id: restoreID)
                }
                guard completed.id == restoreID,
                      completed.completedAt != nil,
                      completed.failureReason == nil else {
                    throw ProjectVaultRuntimeError.unavailable
                }
                model.clearRestoreDestinationMessage(completed)
                if await model.refreshProjectVaultSnapshots() {
                    await model.scan()
                    model.setProjectVaultStatusMessage(
                        "Project Vault restore retry completed and verified."
                    )
                } else {
                    model.setProjectVaultStatusMessage(
                        "Project Vault restore retry completed, but the current Vault state could not be refreshed. Review before taking another action."
                    )
                }
                return true
            } catch is CancellationError {
                _ = await model.refreshProjectVaultSnapshots()
                model.setProjectVaultStatusMessage(CancelCopy.transferStopped)
                return false
            } catch is VaultTransferInterruption {
                _ = await model.refreshProjectVaultSnapshots()
                model.setProjectVaultStatusMessage(CancelCopy.transferStopped)
                return false
            } catch {
                _ = await model.refreshProjectVaultSnapshots()
                model.setProjectVaultStatusMessage(
                    "Project Vault restore retry stopped safely: \(error.localizedDescription). Existing copies were kept."
                )
                model.diagnostics.log(.error, "Project Vault restore retry failed: \(error)")
                return false
            }
        }
    }

    /// Explicit "Resume work" affordance for a restored Active copy. Moves the
    /// workflow status to Prod (the in-progress production stage; the status
    /// enum has no literal inProgress case) through the existing metadata API,
    /// with undo. The default Get Local & Open path never changes workflow
    /// status — only this explicit action does. Offered only for locally
    /// actionable restored copies currently marked Done.
    func canResumeRestoredWork(for song: Song) -> Bool {
        guard let presentation = projectVaultPresentation(for: song) else { return false }
        guard presentation.state == .active || presentation.state == .keepLocal else { return false }
        guard canMutateWorkflowStatus(for: song) else { return false }
        return song.workflowStatus == .done
    }

    func resumeRestoredWork(for song: Song) {
        guard canResumeRestoredWork(for: song) else { return }
        updateWorkflowStatus(for: song, status: .prod)
    }

    func restoreAndOpenFromProjectVault(_ song: Song) {
        guard let runtime = projectVaultRuntime, let snapshot = projectVaultSnapshot(for: song),
              !projectVaultBusySongIDs.contains(song.id), projectVaultRestoreRequest == nil, !projectVaultRestoreOptionsLoading else { return }
        projectVaultRestoreOptionsLoading = true
        Task { [weak self] in
            defer { self?.projectVaultRestoreOptionsLoading = false }
            do {
                let options = try await runtime.restoreOptions(snapshot: snapshot)
                guard let self else { return }
                if let options {
                    self.projectVaultRestoreRequest = ProjectVaultRestoreRequest(song: song, options: options)
                } else {
                    self.enqueueProjectVaultRestore(song)
                }
            } catch {
                self?.diagnostics.scoped(to: .vault).log(.error, "Restore options load failed: \(error.localizedDescription)")
                self?.setProjectVaultStatusMessage("Restore options could not be loaded: \(error.localizedDescription)")
            }
        }
    }

    private func enqueueProjectVaultRestore(_ song: Song, selectedPath: String? = nil, destinationRelativePath: String? = nil) {
        guard let runtime = projectVaultRuntime, let snapshot = projectVaultSnapshot(for: song) else {
            setProjectVaultStatusMessage("Restore is unavailable because no verified Project Vault generation was found.")
            return
        }
        guard !projectVaultBusySongIDs.contains(song.id) else { return }
        // Default restore preserves workflow metadata: it never commits a
        // workflow-status change. Returning to active work is an explicit
        // "Resume work" action (`resumeRestoredWork`). Keep Local pinning for
        // the restored copy happens in the runtime, not here.
        let message = snapshot.linkedArchive == nil
            ? "Restoring the verified project into Active Projects…"
            : "Checking and downloading archive files before restoring into Active Projects…"
        enqueueProjectVaultOperation(for: song, label: "Restore", startMessage: message, tracksRestoreProgress: true) { model in
            do {
                let restored = try await model.waitForProjectVaultSlot {
                    try await runtime.restoreAndOpen(snapshot: model.projectVaultSnapshot(for: song) ?? snapshot, selectedProjectRelativePath: selectedPath, destinationRelativePath: destinationRelativePath)
                }
                model.clearRestoreDestinationMessage(restored)
                await model.refreshProjectVaultSnapshots()
                await model.scan()
                model.setProjectVaultStatusMessage("Restored and verified in Active Projects. Sent to its DAW to open; check any project or plug-in prompts there.")
                return true
            } catch is CancellationError {
                _ = await model.refreshProjectVaultSnapshots()
                model.setProjectVaultStatusMessage(CancelCopy.transferStopped)
                return false
            } catch is VaultTransferInterruption {
                _ = await model.refreshProjectVaultSnapshots()
                model.setProjectVaultStatusMessage(CancelCopy.transferStopped)
                return false
            } catch {
                _ = await model.refreshProjectVaultSnapshots()
                model.setProjectVaultStatusMessage("Restore stopped safely: \(error.localizedDescription). The archive copy was kept.")
                model.diagnostics.log(.error, "Project Vault restore failed: \(error)")
                return false
            }
        }
    }

    private func clearRestoreDestinationMessage(_ restore: VaultRestoreRecord) {
        let destination = Self.vaultCanonicalPath(restore.destinationURL)
        for key in Array(projectVaultOperationMessages.keys)
            where Self.vaultCanonicalPath(URL(fileURLWithPath: key)) == destination {
            projectVaultOperationMessages.removeValue(forKey: key)
        }
    }
}
