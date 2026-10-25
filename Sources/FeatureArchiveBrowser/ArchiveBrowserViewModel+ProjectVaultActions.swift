import AppCore
import Foundation
import NikoMusicCore
import ProjectVaultRuntime

extension ArchiveBrowserViewModel {
    func performProjectVaultPrimaryAction(for song: Song) {
        guard let presentation = projectVaultPresentation(for: song) else {
            try? fileAccess.openLatestCPR(for: song)
            return
        }
        switch presentation.primaryAction {
        case .openInCubase:
            try? fileAccess.openLatestCPR(for: song)
        case .restoreAndOpen:
            restoreAndOpenFromProjectVault(song)
        case .revealArchive:
            revealLinkedArchiveInFinder(for: song)
        case .retry:
            retryProjectVaultTransfer(song)
        case .freeUpSpace:
            // "Ready to free space" is never pre-authorized: route through the
            // existing bound manual archive capture for an explicit fresh
            // confirmation that rechecks every live gate.
            requestArchiveNow(for: song)
        case .review:
            if presentation.retryRestoreID != nil, presentation.reviewAction == nil {
                retryReviewedProjectVaultRestore(for: song)
            } else if case .makeAvailableOfflineInFinder(let generationURL) = presentation.reviewAction {
                setProjectVaultStatusMessage(
                    "Make this Vault copy available offline in Finder, then choose Retry Restore."
                )
                revealProjectVaultGenerationInFinder(generationURL, for: song)
            } else {
                setProjectVaultStatusMessage(presentation.explanation)
            }
        }
    }

    private func retryProjectVaultTransfer(_ song: Song) {
        guard let runtime = projectVaultRuntime, let snapshot = projectVaultSnapshot(for: song) else {
            setProjectVaultStatusMessage("Retry is unavailable because no recoverable Project Vault transfer was found.")
            return
        }
        guard !projectVaultBusySongIDs.contains(song.id) else { return }
        enqueueProjectVaultOperation(for: song, label: "Retry backup", startMessage: "Retrying the preserved Project Vault transfer…") { model in
            do {
                let updated = try await model.waitForProjectVaultSlot {
                    try await runtime.retry(snapshot: model.projectVaultSnapshot(for: song) ?? snapshot)
                }
                model.cacheProjectVaultSnapshot(updated)
                model.rebuildProjectVaultPresentationCache()
                if await model.refreshProjectVaultSnapshots() {
                    model.setProjectVaultStatusMessage(updated.transfer?.isWaitingForProviderUpload == true
                        ? ProjectVaultActivityExplanation.transfer(.awaitingProviderDurability)
                        : "Backup copy verified. Choose Archive Now to remove the Active copy after its safety checks.")
                } else {
                    model.setProjectVaultStatusMessage("Project Vault retry completed, but the current Vault state could not be refreshed. Review before taking another action.")
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
                model.setProjectVaultStatusMessage("Project Vault retry stopped safely: \(error.localizedDescription). Existing copies were kept.")
                model.diagnostics.log(.error, "Project Vault manual retry failed: \(error)")
                return false
            }
        }
    }

    private func revealLinkedArchiveInFinder(for song: Song) {
        do {
            let settings = try settingsStore.loadSettings()
            guard settings.vault.isEnabled,
                  let root = settings.musicRoots.first(where: { $0.id == settings.vault.archiveRootID }),
                  let snapshot = projectVaultSnapshot(for: song), snapshot.transfer == nil,
                  let linked = snapshot.linkedArchive,
                  let url = ProjectArchiveLocationResolver(
                    rootID: root.id,
                    rootURL: try root.resolvedURL(using: FoundationSecurityScopedBookmarks())
                  ).resolve(linked.location),
                  Self.vaultCanonicalPath(url) == Self.vaultCanonicalPath(song.folderPath),
                  FileManager.default.fileExists(atPath: url.path) else {
                throw MusicItemOpenerError.pathOutsideAllowedRoots(song.folderPath)
            }
            fileActions.revealInFinder(url)
        } catch {
            setProjectVaultStatusMessage("The linked archive folder could not be revealed: \(error.localizedDescription)")
        }
    }

    private func revealProjectVaultGenerationInFinder(_ generationURL: URL, for song: Song) {
        do {
            let settings = try settingsStore.loadSettings()
            guard let restore = projectVaultSnapshot(for: song)?.restore,
                  let transferID = restore.archiveTransferID else {
                throw MusicItemOpenerError.pathOutsideAllowedRoots(
                    generationURL.standardizedFileURL
                )
            }
            guard let resolver = ProjectVaultGenerationReviewResolver(settings: settings),
                  let resolved = resolver.resolveGeneration(
                    generationURL,
                    projectID: restore.projectID,
                    transferID: transferID
                  ) else {
                throw MusicItemOpenerError.pathOutsideAllowedRoots(
                    generationURL.standardizedFileURL
                )
            }
            fileActions.revealInFinder(resolved)
        } catch let error as MusicItemOpenerError {
            setProjectVaultStatusMessage(ArchiveFileAccessModel.statusMessage(for: error))
            diagnostics.log(.warning, "Project Vault generation reveal refused: \(error)")
        } catch {
            setProjectVaultStatusMessage(
                "The Vault copy can’t be shown in Finder: \(error.localizedDescription)"
            )
            diagnostics.log(.warning, "Project Vault generation reveal failed: \(error)")
        }
    }
}

// MARK: - Restore

extension ArchiveBrowserViewModel {
    func confirmProjectVaultRestore(selectedPath: String? = nil, destinationRelativePath: String? = nil) {
        guard let request = vaultDialogs.projectVaultRestoreRequest else { return }
        let destination = destinationRelativePath ?? request.options.destinationRelativePath
        guard request.options.destinationIssue(for: destination) == nil,
              selectedPath == nil || request.options.versions.contains(where: { $0.relativePath == selectedPath }) else { return }
        vaultDialogs.closeRestore()
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
    /// with undo. The default Restore & Open path never changes workflow
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
              !projectVaultBusySongIDs.contains(song.id), vaultDialogs.beginRestoreOptionsLoad() else { return }
        Task { [weak self] in
            defer { self?.vaultDialogs.endRestoreOptionsLoad() }
            do {
                let options = try await runtime.restoreOptions(snapshot: snapshot)
                guard let self else { return }
                if let options {
                    self.vaultDialogs.presentRestore(ProjectVaultRestoreRequest(song: song, options: options))
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
            setProjectVaultStatusMessage("There’s no verified Vault copy to restore yet.")
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
                model.setProjectVaultStatusMessage(Self.restoreCompletedMessage(dryRunOpen: model.runtime.dryRunOpen))
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

    /// Status after a verified restore. Dry-run opening (test mode,
    /// `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1`) hands the project to no DAW, so the
    /// message must not claim it did.
    static func restoreCompletedMessage(dryRunOpen: Bool) -> String {
        dryRunOpen
            ? "Restored and verified in Active Projects. Dry run: not sent to a DAW."
            : "Restored and verified in Active Projects. Sent to its DAW to open; check any project or plug-in prompts there."
    }

    private func clearRestoreDestinationMessage(_ restore: VaultRestoreRecord) {
        let destination = Self.vaultCanonicalPath(restore.destinationURL)
        for key in Array(projectVaultOperationMessages.keys)
            where Self.vaultCanonicalPath(URL(fileURLWithPath: key)) == destination {
            vaultOperations.removeOperationMessage(forKey: key)
        }
    }
}

// MARK: - Recovering an interrupted archive

extension ArchiveBrowserViewModel {
    func canRecoverInterruptedProject(_ song: Song) -> Bool {
        guard let transfer = projectVaultSnapshot(for: song)?.transfer,
              transfer.state == .recoveryRequired, let origin = transfer.error?.origin else { return false }
        return [.removingActiveCopy, .evictingProviderCache].contains(origin)
    }

    func recoverInterruptedProject(_ song: Song) {
        guard canRecoverInterruptedProject(song), let runtime = projectVaultRuntime,
              let snapshot = projectVaultSnapshot(for: song) else { return }
        enqueueProjectVaultOperation(for: song, label: "Recover", startMessage: "Verifying the archive and preserving existing Active files…") { model in
            do {
                _ = try await model.waitForProjectVaultSlot {
                    try await runtime.recoverInterruptedArchive(snapshot: snapshot)
                }
                await model.refreshProjectVaultSnapshots()
                await model.scan()
                model.setProjectVaultStatusMessage("Recovered and verified in Active Projects. Any previous Active folder was preserved; use Reveal Preserved Files in song details.")
                return true
            } catch {
                await model.refreshProjectVaultSnapshots()
                model.setProjectVaultStatusMessage("Recovery stopped safely: \(error.localizedDescription) Existing copies were kept.")
                return false
            }
        }
    }

    func preservedProjectVaultCopy(for song: Song) -> URL? {
        guard let transfer = projectVaultSnapshot(for: song)?.transfer,
              let active = projectVaultPresentationContext?.activeRoot,
              let root = try? active.resolvedURL(using: FoundationSecurityScopedBookmarks()) else { return nil }
        let recoveryRoot = VaultFolders.recovery(in: root, transferID: transfer.id)
        let safety = PathSafety()
        guard safety.isResolvedContainedWithoutNestedSymlinks(recoveryRoot, in: root) else { return nil }
        return transfer.preservedActiveCopies?.reversed().first {
            safety.isResolvedContainedWithoutNestedSymlinks($0, in: recoveryRoot)
                && $0 != recoveryRoot && FileManager.default.fileExists(atPath: $0.path)
        }
    }

    func revealPreservedProjectVaultCopy(for song: Song) {
        guard let url = preservedProjectVaultCopy(for: song) else { return }
        fileActions.revealInFinder(url)
    }
}
