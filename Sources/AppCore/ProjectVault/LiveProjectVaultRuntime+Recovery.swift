import Foundation
import NikoMusicCore

extension LiveProjectVaultRuntime {
    public func recoverInterruptedArchive(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
        let lease = try acquireMutationLease()
        defer { releaseMutationLease(lease) }
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        guard !settings.vault.automationEmergencyStop else { throw ProjectVaultRuntimeError.emergencyStop }
        guard let requested = snapshot.transfer,
              let transfer = try latestTransfer(projectID: snapshot.record.id),
              transfer.id == requested.id, transfer.state == .recoveryRequired else {
            throw ProjectVaultRuntimeError.unavailable
        }
        // Fail closed Keep Local pin before any materialization or before
        // recovery sets the partial Active folder aside. Reuses the shared
        // restore helper so ordinary, linked, retry, and recovery paths pin
        // the same validated destination; a settings-write failure aborts
        // before any bytes move and never reports an unpinned restore.
        try prePersistRestoreProtection(projectID: transfer.projectID, relativePath: transfer.sourceURL.lastPathComponent, activeRoot: configuration.active.url)
        let activity = activityProbe
        let store = settingsStore
        let provider = archiveProvider(root: configuration.archive.url)
        let recovery = try LocalVaultTransferEngine(
            activeRoot: configuration.active.url, archiveRoot: configuration.archive.url,
            store: transferStore, provider: provider,
            writeAdmission: makeWriteAdmission(settings: settings),
            removalAdmission: { record in
                let current = try store.loadSettings()
                guard current.vault.isEnabled else { throw ProjectVaultRuntimeError.disabled }
                guard !current.vault.automationEmergencyStop else { throw ProjectVaultRuntimeError.emergencyStop }
                guard current.vault.activeRootID == configuration.active.id,
                      current.vault.archiveRootID == configuration.archive.id else { throw ProjectVaultRuntimeError.unavailable }
                // Recovery only sets the partial Active folder aside before
                // restoring, so Keep Local and backup confirmation do not apply;
                // an open DAW or open files still do.
                try await Self.requireProjectIdle(activity, in: record.sourceURL)
            }
        )
        let verified = try await recovery.recoverInterruptedRemoval(id: transfer.id)
        let restore = LocalVaultRestoreEngine(
            activeRoot: configuration.active.url, archiveRoot: configuration.archive.url,
            activeRootID: configuration.active.id, resolver: transferStore,
            store: transferStore, projectionStore: transferStore, provider: provider,
            catalog: catalogStore, projectOpener: projectOpener,
            writeAdmission: makeWriteAdmission(settings: settings),
            linkedArchiveValidation: linkedArchiveValidation(configuration: configuration)
        )
        do {
            let record = try await restore.restoreAndOpen(
                projectID: verified.projectID, destinationRelativePath: verified.sourceURL.lastPathComponent
            )
            persistRestoredKeepLocal(projectID: record.projectID, destinationURL: record.destinationURL)
            return record
        } catch {
            persistKeepLocalForVerifiedDestination(projectID: verified.projectID)
            throw error
        }
    }

    public func retry(snapshot: ProjectVaultRuntimeSnapshot) async throws -> ProjectVaultRuntimeSnapshot {
        let lease = try acquireMutationLease()
        defer { releaseMutationLease(lease) }
        let configuration = try configuration()
        let settings = try settingsStore.loadSettings()
        guard !settings.vault.automationEmergencyStop else {
            throw ProjectVaultRuntimeError.emergencyStop
        }
        guard let failed = snapshot.transfer, failed.state == .failedRecoverable else {
            throw ProjectVaultRuntimeError.unavailable
        }
        guard let origin = failed.error?.origin,
              VaultTransferRetryPolicy.permitsNondestructiveArchiveOrigin(origin) else {
            throw ProjectVaultRuntimeError.unavailable
        }
        let engine = try LocalVaultTransferEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            store: transferStore,
            provider: archiveProvider(root: configuration.archive.url),
            now: now,
            recoveryPolicy: recoveryPolicy,
            writeAdmission: makeWriteAdmission(settings: settings)
        )
        guard let retried = await engine.retryRecoverableTransfer(id: failed.id) else {
            throw ProjectVaultRuntimeError.unavailable
        }
        guard retried.id == failed.id, (retried.state == .archiveVerified || retried.isWaitingForProviderUpload) else {
            throw ProjectVaultRuntimeError.archiveFailed(
                retried.error?.message
                    ?? "The recoverable transfer stopped in \(retried.state.rawValue) before verification."
            )
        }
        if retried.state == .archiveVerified {
            try settingsStore.updateSettings { $0.vault.lastSuccessfulVerificationAt = now() }
        }
        // Project the verified transfer onto the current catalog entry, as
        // `snapshots()` would, so the caller does not cache the stale input record.
        guard let entry = try catalogStore.loadEntries().first(where: { $0.record.id == snapshot.record.id }) else {
            return ProjectVaultRuntimeSnapshot(record: snapshot.record, transfer: retried)
        }
        return self.snapshot(entry: entry, transfer: retried, configuration: configuration)
    }

    /// The persisted backoff is also used by the mounted browser to wake recovery.
    /// Keep eligibility here so UI timers cannot bypass the engine's retry budget.
    public func nextAutomaticRecoveryDate() async throws -> Date? {
        _ = try configuration()
        guard !(try settingsStore.loadSettings()).vault.automationEmergencyStop else { return nil }
        let candidates = VaultTransferRecoveryPolicy.candidates(from: try transferStore.recoverableRecords())
        return candidates.compactMap { record -> Date? in
            if record.isWaitingForProviderUpload { return record.nextRetryAt }
            guard record.state == .failedRecoverable,
                  record.retryCount < recoveryPolicy.maximumAutomaticAttempts,
                  let origin = record.error?.origin,
                  VaultTransferRetryPolicy.permitsNondestructiveArchiveOrigin(origin) else { return nil }
            return record.nextRetryAt ?? now()
        }.min()
    }

    public func recoverAtLaunch() async {
        if let recoveryTask {
            await recoveryTask.task.value
            return
        }
        let id = UUID()
        let task = Task { await self.performRecoveryAtLaunch() }
        recoveryTask = (id, task)
        await task.value
        if recoveryTask?.id == id { recoveryTask = nil }
    }

    private func performRecoveryAtLaunch() async {
        guard let lease = try? acquireMutationLease() else { return }
        defer { releaseMutationLease(lease) }
        guard let configuration = try? configuration() else { return }
        guard let settings = try? settingsStore.loadSettings(),
              !settings.vault.automationEmergencyStop else { return }
        let provider = archiveProvider(root: configuration.archive.url)
        if let transferEngine = try? LocalVaultTransferEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            store: transferStore,
            provider: provider,
            now: now,
            recoveryPolicy: recoveryPolicy,
            writeAdmission: makeWriteAdmission(settings: settings)
        ) { _ = await transferEngine.recoverAtLaunch() }
        let restoreEngine = LocalVaultRestoreEngine(
            activeRoot: configuration.active.url,
            archiveRoot: configuration.archive.url,
            activeRootID: configuration.active.id,
            resolver: transferStore,
            store: transferStore,
            projectionStore: transferStore,
            provider: provider,
            catalog: catalogStore,
            projectOpener: projectOpener,
            writeAdmission: makeWriteAdmission(settings: settings),
            linkedArchiveValidation: linkedArchiveValidation(configuration: configuration)
        )
        _ = await restoreEngine.recoverAtLaunch()
    }
}
