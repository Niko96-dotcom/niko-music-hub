import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    func projectVaultPresentation(for song: Song) -> ProjectVaultCardPresentation? {
        guard let settings = try? settingsStore.loadSettings(), settings.vault.isEnabled else { return nil }
        if let snapshot = projectVaultSnapshot(for: song) {
            var record = snapshot.record
            record.pinned = settings.vault.keepLocalProjectIDs.contains(snapshot.transfer?.sourceURL.path ?? song.id)
            let transferState = snapshot.transfer?.state == .archiveVerified ? nil : snapshot.transfer?.state
            return ProjectVaultCardPresentation(record: record, transferState: transferState)
        }
        let path = song.folderPath.standardizedFileURL.resolvingSymlinksInPath()
        guard let active = settings.musicRoots.first(where: {
            $0.id == settings.vault.activeRootID && Self.vaultContains($0.fallbackURL, path)
        }) else { return nil }
        let record = ProjectRecord(
            canonicalTitle: song.effectiveDisplayTitle,
            locations: [ProjectLocation(rootID: active.id, relativePath: song.folderPath.lastPathComponent, kind: .active)],
            pinned: settings.vault.keepLocalProjectIDs.contains(song.id),
            workflowState: song.workflowStatus,
            lastActivityAt: song.effectiveLatestCPR?.modifiedAt
        )
        return ProjectVaultCardPresentation(record: record)
    }

    func canArchiveInProjectVault(_ song: Song) -> Bool {
        guard projectVaultRuntime != nil,
              projectVaultPresentation(for: song)?.state != .archived else { return false }
        return !projectVaultBusySongIDs.contains(song.id)
    }

    func setProjectKeepLocal(_ keepLocal: Bool, for song: Song) {
        do {
            let key = projectVaultSnapshot(for: song)?.transfer?.sourceURL.path ?? song.id
            try settingsStore.updateSettings { settings in
                if keepLocal { settings.vault.keepLocalProjectIDs.insert(key) }
                else { settings.vault.keepLocalProjectIDs.remove(key) }
            }
            objectWillChange.send()
        } catch {
            diagnostics.log(.error, "Project Vault Keep Local setting failed: \(error)")
            setStatusMessage("Keep Local could not be saved. No project files were changed.")
        }
    }

    func archiveInProjectVault(_ song: Song, trigger: ProjectVaultArchiveTrigger = .manual) {
        guard let projectVaultRuntime, !projectVaultBusySongIDs.contains(song.id) else { return }
        projectVaultBusySongIDs.insert(song.id)
        setStatusMessage(trigger == .workflowDone ? "Done — checking Project Vault safety…" : "Archiving and verifying a Project Vault copy…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.projectVaultBusySongIDs.remove(song.id) }
            do {
                let snapshot = try await projectVaultRuntime.archive(song: song, trigger: trigger)
                self.projectVaultRetryTasks.removeValue(forKey: song.id)?.cancel()
                self.cacheProjectVaultSnapshot(snapshot)
                await self.refreshProjectVaultSnapshots()
                let activeRetained = FileManager.default.fileExists(atPath: song.folderPath.path)
                self.setStatusMessage(activeRetained
                    ? "Archived and verified. The Active copy was kept."
                    : "Done and archived. The verified project is ready to restore when needed.")
            } catch let error as ProjectVaultRuntimeError where trigger == .workflowDone {
                self.setStatusMessage("Marked Done. \(error.localizedDescription)")
                self.diagnostics.log(.warning, "Done auto-archive postponed: \(error)")
                self.scheduleDoneArchiveRetry(for: song)
            } catch {
                self.setStatusMessage("Project Vault could not archive this project: \(error.localizedDescription). No source files were changed.")
                self.diagnostics.log(.error, "Project Vault archive failed: \(error)")
            }
        }
    }

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
        case .review:
            setStatusMessage(presentation.explanation)
        }
    }

    func refreshProjectVaultSnapshots() async {
        guard let projectVaultRuntime else { return }
        do {
            let snapshots = try await projectVaultRuntime.snapshots()
            projectVaultSnapshotsByPath.removeAll()
            snapshots.forEach(cacheProjectVaultSnapshot)
            mergeArchivedVaultSongs(from: snapshots)
            enqueueDoneVaultProjectsIfNeeded()
        } catch ProjectVaultRuntimeError.unavailable {
            projectVaultSnapshotsByPath.removeAll()
        } catch {
            diagnostics.log(.error, "Project Vault state refresh failed: \(error)")
        }
    }

    private func enqueueDoneVaultProjectsIfNeeded() {
        for song in songs where song.workflowStatus == .done {
            let transfer = projectVaultSnapshot(for: song)?.transfer
            let isAlreadyArchived = transfer.map {
                [.archiveVerified, .archivedLocal, .archivedOnlineOnly].contains($0.state)
            } ?? false
            if !isAlreadyArchived, !projectVaultBusySongIDs.contains(song.id) {
                archiveInProjectVault(song, trigger: .workflowDone)
            }
        }
    }

    private func scheduleDoneArchiveRetry(for song: Song) {
        guard projectVaultRetryTasks[song.id] == nil else { return }
        projectVaultRetryTasks[song.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled else { return }
            self.projectVaultRetryTasks.removeValue(forKey: song.id)
            guard let current = self.songs.first(where: { $0.id == song.id }),
                  current.workflowStatus == .done else { return }
            self.archiveInProjectVault(current, trigger: .workflowDone)
        }
    }

    private func restoreAndOpenFromProjectVault(_ song: Song) {
        guard let runtime = projectVaultRuntime, let snapshot = projectVaultSnapshot(for: song) else {
            setStatusMessage("Restore is unavailable because no verified Project Vault generation was found.")
            return
        }
        guard !projectVaultBusySongIDs.contains(song.id) else { return }
        projectVaultBusySongIDs.insert(song.id)
        setStatusMessage("Restoring the verified project into Active Projects…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.projectVaultBusySongIDs.remove(song.id) }
            do {
                _ = try await runtime.restoreAndOpen(snapshot: snapshot)
                await self.refreshProjectVaultSnapshots()
                await self.scan()
                self.setStatusMessage("Restored, verified, and opened in Cubase.")
            } catch {
                self.setStatusMessage("Restore stopped safely: \(error.localizedDescription). The archive copy was kept.")
                self.diagnostics.log(.error, "Project Vault restore failed: \(error)")
            }
        }
    }

    private func projectVaultSnapshot(for song: Song) -> ProjectVaultRuntimeSnapshot? {
        projectVaultSnapshotsByPath[Self.vaultCanonicalPath(song.folderPath)]
    }

    private func cacheProjectVaultSnapshot(_ snapshot: ProjectVaultRuntimeSnapshot) {
        if let transfer = snapshot.transfer {
            projectVaultSnapshotsByPath[Self.vaultCanonicalPath(transfer.sourceURL)] = snapshot
            projectVaultSnapshotsByPath[Self.vaultCanonicalPath(transfer.destinationURL)] = snapshot
        }
    }

    private func mergeArchivedVaultSongs(from snapshots: [ProjectVaultRuntimeSnapshot]) {
        let archived = snapshots.compactMap { snapshot -> Song? in
            guard let transfer = snapshot.transfer,
                  [.archiveVerified, .archivedLocal, .archivedOnlineOnly].contains(transfer.state),
                  !FileManager.default.fileExists(atPath: transfer.sourceURL.path),
                  FileManager.default.fileExists(atPath: transfer.destinationURL.path) else { return nil }
            let detector = CPRVersionDetector()
            let versions = (try? detector.detectVersions(in: transfer.destinationURL)) ?? []
            return Song(
                folderPath: transfer.destinationURL,
                originalFolderName: transfer.sourceURL.lastPathComponent,
                displayTitle: snapshot.record.canonicalTitle,
                projectVersions: versions,
                latestCPR: detector.latestCPR(from: versions),
                workflowStatus: snapshot.record.workflowState
            )
        }
        guard !archived.isEmpty else { return }
        mutateCatalog {
            let archivedIDs = Set(archived.map(\.id))
            let archivedSourcePaths: Set<String> = Set(snapshots.compactMap { snapshot -> String? in
                guard let transfer = snapshot.transfer,
                      !FileManager.default.fileExists(atPath: transfer.sourceURL.path) else { return nil }
                return Self.vaultCanonicalPath(transfer.sourceURL)
            })
            songs.removeAll {
                archivedIDs.contains($0.id)
                    || archivedSourcePaths.contains(Self.vaultCanonicalPath($0.folderPath))
            }
            songs.append(contentsOf: archived)
        }
    }

    private static func vaultCanonicalPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
        for alias in ["/private/var", "/private/tmp"] {
            if path == alias { return String(alias.dropFirst("/private".count)) }
            if path.hasPrefix(alias + "/") { return String(path.dropFirst("/private".count)) }
        }
        return path
    }

    private static func vaultContains(_ root: URL, _ candidate: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count >= rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
