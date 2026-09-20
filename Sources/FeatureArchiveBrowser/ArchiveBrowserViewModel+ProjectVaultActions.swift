import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func performProjectVaultPrimaryAction(for song: Song) {
        guard let presentation = projectVaultPresentation(for: song) else {
            try? openLatestCPR(for: song)
            return
        }
        switch presentation.primaryAction {
        case .openInCubase:
            try? openLatestCPR(for: song)
        case .restoreAndOpen:
            restoreAndOpenFromProjectVault(song)
        case .revealArchive:
            revealLinkedArchiveInFinder(for: song)
        case .retry:
            retryProjectVaultTransfer(song)
        case .review:
            if presentation.retryRestoreID != nil, presentation.reviewAction == nil {
                retryReviewedProjectVaultRestore(for: song)
            } else if case .makeAvailableOfflineInFinder(let generationURL) = presentation.reviewAction {
                setProjectVaultStatusMessage(
                    "Make this exact archive generation available offline in Finder, then choose Retry Get Local."
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
            setProjectVaultStatusMessage(musicItemOpenerStatusMessage(error))
            diagnostics.log(.warning, "Project Vault generation reveal refused: \(error)")
        } catch {
            setProjectVaultStatusMessage(
                "Project Vault generation cannot be revealed: \(error.localizedDescription)"
            )
            diagnostics.log(.warning, "Project Vault generation reveal failed: \(error)")
        }
    }
}
