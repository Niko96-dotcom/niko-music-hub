import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    /// Cancels a bounded Done retry without reusing its approval.
    func cancelDoneArchiveRetry(for songID: String) {
        projectVaultRetryTasks.removeValue(forKey: songID)?.cancel()
        projectVaultRetryAttemptCounts.removeValue(forKey: songID)
    }
    // MARK: - Bound authorization (final contract)
    //
    // Every explicit confirmation captures its authorization BEFORE the dialog
    // is presented. The exact captured token travels
    // pendingArchiveConfirmation -> confirmPendingArchive ->
    // archiveInProjectVault(authorization:) -> queue closure -> bounded Done
    // retries. It is never re-captured or strengthened at execution: a
    // copy-only token stays copy-only even when live settings later become
    // permissive, and any source/root/identity drift fails closed in the
    // runtime. The compatibility `archive(song:trigger:)` overload (nil
    // authorization, including automatic Done without confirmation) is always
    // copy-only: a new destructive action always needs a fresh confirmation.
    // Undo or a status change away from Done revokes the matching capture,
    // dialog, queued Done operation, retry budget, and inflight Done task; a
    // revoked approval is never reused by a later retry or relaunch.

    func requestArchiveNow(for song: Song) {
        guard canArchiveInProjectVault(song) else { return }
        startBoundArchiveCapture(for: song, trigger: .manual)
    }

    func requestWorkflowDoneArchive(for song: Song) {
        guard canMutateWorkflowStatus(for: song), song.workflowStatus != .done else { return }
        guard canArchiveInProjectVault(song) else {
            applyWorkflowStatus(.done, for: song)
            return
        }
        startBoundArchiveCapture(for: song, trigger: .workflowDone)
    }

    /// Fresh bounded Done confirmation after identity review.
    /// The user already committed `.done` via `confirmPendingArchive` before the runtime
    /// raised identity ambiguity, so `requestWorkflowDoneArchive` would reject the
    /// already-done song and strand the operation. This re-issues the same explicit
    /// Done confirmation without mutating workflow status or inventing undo.
    func requestWorkflowDoneReconfirmation(for song: Song) {
        guard canArchiveInProjectVault(song),
              songs.first(where: { $0.id == song.id }) != nil else { return }
        startBoundArchiveCapture(for: song, trigger: .workflowDone)
    }

    /// Cancels an in-flight bound capture for one song (or every capture when
    /// `songID` is nil). Per-song ownership: cancelling one song never drops a
    /// different song's dialog or capture. Bumping the generation guarantees a
    /// superseded capture can never present a stale late modal after its awaits.
    func cancelBoundArchiveCapture(for songID: String? = nil) {
        if let songID {
            if let pendingSong = pendingArchiveConfirmation?.songID,
               pendingSong != songID,
               boundArchiveCaptureSongID != songID {
                return
            }
            if let capturing = boundArchiveCaptureSongID, capturing != songID {
                return
            }
            let ownsDialog = pendingArchiveConfirmation?.songID == songID
            let ownsCapture = boundArchiveCaptureSongID == songID
            if !ownsDialog && !ownsCapture {
                return
            }
            projectVaultAuthCaptureGeneration &+= 1
            projectVaultAuthCaptureTask?.cancel()
            projectVaultAuthCaptureTask = nil
            if boundArchiveCaptureSongID == songID {
                boundArchiveCaptureSongID = nil
            }
            if pendingArchiveConfirmation?.songID == songID {
                pendingArchiveConfirmation = nil
            }
            return
        }
        projectVaultAuthCaptureGeneration &+= 1
        projectVaultAuthCaptureTask?.cancel()
        projectVaultAuthCaptureTask = nil
        boundArchiveCaptureSongID = nil
        pendingArchiveConfirmation = nil
    }

    /// Asynchronously captures the bound authorization before presenting the
    /// dialog. Manual intent requests removal; Done intent requests the
    /// current settings ceiling. A removal request that is already gated falls
    /// back to a copy-only capture so the dialog agrees the token; only a
    /// capture that cannot even copy surfaces an actionable message with no
    /// queued destruction. A missing current song never falls back to a wrong
    /// source: the capture aborts and the runtime rechecks the binding.
    private func startBoundArchiveCapture(for song: Song, trigger: ProjectVaultArchiveTrigger) {
        projectVaultAuthCaptureGeneration &+= 1
        let generation = projectVaultAuthCaptureGeneration
        projectVaultAuthCaptureTask?.cancel()
        // A replacement supersedes any presented dialog for the previous
        // capture; the new capture re-presents only when it is still current.
        pendingArchiveConfirmation = nil
        let songID = song.id
        boundArchiveCaptureSongID = songID
        projectVaultAuthCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let probe = self.projectVaultAuthCaptureProbe {
                await probe()
            }
            guard !Task.isCancelled, self.projectVaultAuthCaptureGeneration == generation else { return }
            guard let runtime = self.projectVaultRuntime else {
                if self.projectVaultAuthCaptureGeneration == generation,
                   self.boundArchiveCaptureSongID == songID {
                    self.boundArchiveCaptureSongID = nil
                }
                return
            }
            guard let current = self.songs.first(where: { $0.id == songID }) else {
                if self.projectVaultAuthCaptureGeneration == generation,
                   self.boundArchiveCaptureSongID == songID {
                    self.boundArchiveCaptureSongID = nil
                }
                return
            }
            let catalogID = self.projectVaultSnapshot(for: current)?.record.id
            let settings = try? self.settingsStore.loadSettings()
            let requestedRemoving: Bool
            switch trigger {
            case .manual:
                requestedRemoving = true
            case .workflowDone:
                if let vault = settings?.vault {
                    requestedRemoving = ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(vault)
                } else {
                    requestedRemoving = false
                }
            case .backupCopy:
                requestedRemoving = false
            @unknown default:
                requestedRemoving = false
            }
            let authorization: ProjectVaultArchiveAuthorization
            // The dialog song for the token. Refreshed after each await so a
            // song change never falls back to a stale source.
            var liveSong = current
            if requestedRemoving {
                do {
                    authorization = try await runtime.captureArchiveAuthorization(
                        for: liveSong,
                        trigger: trigger,
                        removingActiveCopy: true,
                        catalogProjectID: catalogID
                    )
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, self.projectVaultAuthCaptureGeneration == generation else { return }
                    guard let retryCurrent = self.songs.first(where: { $0.id == songID }) else { return }
                    let retryCatalog = self.projectVaultSnapshot(for: retryCurrent)?.record.id
                    do {
                        authorization = try await runtime.captureArchiveAuthorization(
                            for: retryCurrent,
                            trigger: trigger,
                            removingActiveCopy: false,
                            catalogProjectID: retryCatalog
                        )
                        liveSong = retryCurrent
                    } catch is CancellationError {
                        return
                    } catch let copyError {
                        guard !Task.isCancelled, self.projectVaultAuthCaptureGeneration == generation else { return }
                        if self.boundArchiveCaptureSongID == songID {
                            self.boundArchiveCaptureSongID = nil
                        }
                        self.setProjectVaultStatusMessage("\(copyError.localizedDescription)")
                        self.diagnostics.log(.warning, "Archive authorization capture failed: \(copyError)")
                        return
                    }
                }
            } else {
                do {
                    authorization = try await runtime.captureArchiveAuthorization(
                        for: liveSong,
                        trigger: trigger,
                        removingActiveCopy: false,
                        catalogProjectID: catalogID
                    )
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, self.projectVaultAuthCaptureGeneration == generation else { return }
                    if self.boundArchiveCaptureSongID == songID {
                        self.boundArchiveCaptureSongID = nil
                    }
                    self.setProjectVaultStatusMessage("\(error.localizedDescription)")
                    self.diagnostics.log(.warning, "Archive authorization capture failed: \(error)")
                    return
                }
            }
            guard !Task.isCancelled, self.projectVaultAuthCaptureGeneration == generation else { return }
            guard let live = self.songs.first(where: { $0.id == songID }),
                  live.id == authorization.songID,
                  authorization.trigger == trigger else {
                if self.projectVaultAuthCaptureGeneration == generation,
                   self.boundArchiveCaptureSongID == songID {
                    self.boundArchiveCaptureSongID = nil
                }
                return
            }
            // The dialog must agree the captured token; a copy-only token can
            // never escalate, however permissive live settings become.
            let willRemove = authorization.permitsRemoval
            let liveSettings = try? self.settingsStore.loadSettings()
            let backupConfirmed = liveSettings?.vault.independentBackupConfirmed ?? false
            // Bind the dialog title to the live song; the authorization itself
            // carries no title and the runtime revalidates the bound source.
            _ = liveSong
            if self.projectVaultAuthCaptureGeneration != generation {
                return
            }
            if self.boundArchiveCaptureSongID == songID {
                self.boundArchiveCaptureSongID = nil
            }
            self.pendingArchiveConfirmation = ProjectVaultArchiveConfirmation(
                songID: live.id,
                songTitle: live.effectiveDisplayTitle,
                trigger: trigger,
                willRemoveActiveCopy: willRemove,
                independentBackupConfirmed: backupConfirmed,
                authorization: authorization
            )
        }
    }

    func confirmPendingArchive() {
        guard let pending = pendingArchiveConfirmation,
              let song = songs.first(where: { $0.id == pending.songID }) else { return }
        // Fail closed on a dialog/token disagreement: a copy-only token can
        // never authorize removal, and a mismatched song/trigger queues nothing.
        if let authorization = pending.authorization {
            guard authorization.songID == song.id,
                  authorization.trigger == pending.trigger,
                  pending.willRemoveActiveCopy == authorization.permitsRemoval else { return }
        } else if pending.willRemoveActiveCopy {
            return
        }
        pendingArchiveConfirmation = nil
        projectVaultAuthCaptureTask = nil
        boundArchiveCaptureSongID = nil
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
            archiveInProjectVault(updated, trigger: .workflowDone, authorization: pending.authorization)
            return
        }
        archiveInProjectVault(song, trigger: pending.trigger, authorization: pending.authorization)
    }

    func cancelPendingArchive() {
        projectVaultAuthCaptureGeneration &+= 1
        projectVaultAuthCaptureTask?.cancel()
        projectVaultAuthCaptureTask = nil
        boundArchiveCaptureSongID = nil
        pendingArchiveConfirmation = nil
    }

    func archiveInProjectVault(_ song: Song, trigger: ProjectVaultArchiveTrigger = .manual, authorization: ProjectVaultArchiveAuthorization? = nil) {
        guard let projectVaultRuntime,
              canArchiveInProjectVault(song),
              !projectVaultBusySongIDs.contains(song.id) else { return }
        // Fail closed before queueing: a token bound to another song/trigger
        // (or a removal token on a backup copy) never queues destruction; the
        // runtime rechecks the same binding after its awaits.
        if let authorization {
            guard authorization.songID == song.id,
                  authorization.trigger == trigger else {
                setProjectVaultStatusMessage(ProjectVaultAuthorizationError.songMismatch.localizedDescription)
                return
            }
            if trigger == .backupCopy, authorization.permitsRemoval {
                setProjectVaultStatusMessage(ProjectVaultAuthorizationError.backupCopyRemovalForbidden.localizedDescription)
                return
            }
        }
        let capturedAuthorization = authorization
        enqueueProjectVaultOperation(
            for: song, label: trigger == .backupCopy ? "Backup" : "Archive",
            startMessage: trigger == .workflowDone ? "Done — checking Project Vault safety…" : "Archiving and verifying a Project Vault copy…",
            trigger: trigger
        ) { model in
            do {
                // Never fall back to a stale source: a missing current song
                // queues nothing and the runtime revalidates the bound source.
                guard let currentSong = model.songs.first(where: { $0.id == song.id }) else {
                    model.setProjectVaultStatusMessage("The project is no longer available. Nothing was archived.")
                    return false
                }
                if let capturedAuthorization {
                    guard capturedAuthorization.songID == currentSong.id else {
                        model.setProjectVaultStatusMessage(ProjectVaultAuthorizationError.songMismatch.localizedDescription)
                        return false
                    }
                }
                let snapshot: ProjectVaultRuntimeSnapshot
                if let capturedAuthorization {
                    snapshot = try await model.waitForProjectVaultSlot {
                        try await projectVaultRuntime.archive(song: currentSong, trigger: trigger, authorization: capturedAuthorization)
                    }
                } else {
                    snapshot = try await model.waitForProjectVaultSlot {
                        try await projectVaultRuntime.archive(song: currentSong, trigger: trigger)
                    }
                }
                model.projectVaultRetryTasks.removeValue(forKey: song.id)?.cancel()
                model.projectVaultRetryAttemptCounts.removeValue(forKey: song.id)
                model.cacheProjectVaultSnapshot(snapshot)
                model.rebuildProjectVaultPresentationCache()
                await model.refreshProjectVaultSnapshots()
                if snapshot.transfer?.isWaitingForProviderUpload == true {
                    model.setProjectVaultStatusMessage(ProjectVaultActivityExplanation.transfer(.awaitingProviderDurability))
                    return true
                }
                let livePath = model.songs.first(where: { $0.id == song.id })?.folderPath ?? song.folderPath
                let activeRetained = FileManager.default.fileExists(atPath: livePath.path)
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
                    guard let liveSong = model.songs.first(where: { $0.id == song.id }) else {
                        model.setProjectVaultStatusMessage("The project is no longer available. Nothing was archived.")
                        return false
                    }
                    await model.beginIdentityReview(
                        for: liveSong,
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
                        model.scheduleDoneArchiveRetry(for: song, authorization: capturedAuthorization)
                    }
                    return false
                }
                model.setProjectVaultStatusMessage("Archive did not complete: \(error.localizedDescription)")
                model.diagnostics.log(.error, "Project Vault archive failed: \(error)")
                return false
            } catch let error as ProjectVaultAuthorizationError {
                _ = await model.refreshProjectVaultSnapshots()
                if trigger == .workflowDone {
                    model.setProjectVaultStatusMessage("Marked Done. \(error.localizedDescription)")
                    model.diagnostics.log(.warning, "Done auto-archive postponed: \(error)")
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

    private func scheduleDoneArchiveRetry(for song: Song, authorization: ProjectVaultArchiveAuthorization? = nil) {
        let attemptCount = projectVaultRetryAttemptCounts[song.id, default: 0]
        guard projectVaultRetryTasks[song.id] == nil, attemptCount < 3 else { return }
        projectVaultRetryAttemptCounts[song.id] = attemptCount + 1
        // Bounded retries retain the exact confirmation-time token (never a
        // fresh capture): a copy-only token stays copy-only even when live
        // settings later become permissive.
        let retryAuthorization = authorization
        let retryDelay = projectVaultDoneRetryDelay
        projectVaultRetryTasks[song.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: retryDelay)
            guard let self, !Task.isCancelled else { return }
            self.projectVaultRetryTasks.removeValue(forKey: song.id)
            guard let current = self.songs.first(where: { $0.id == song.id }),
                  current.workflowStatus == .done else { return }
            self.archiveInProjectVault(current, trigger: .workflowDone, authorization: retryAuthorization)
        }
    }
}
