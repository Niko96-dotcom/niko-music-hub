import Foundation
import NikoMusicCore

extension LiveProjectVaultRuntime {
    func makeWriteAdmission(settings _: AppSettings) -> LocalVaultTransferEngine.WriteAdmission {
        let capacityProbe = self.capacityProbe
        let settingsStore = self.settingsStore
        return { request, operation in
            let projectedCopyBytes: Int64
            switch request.projection {
            case .persistedManifest(let manifest, let supplement):
                do {
                    projectedCopyBytes = try capacityProbe.conservativeProjectedBytes(
                        manifest: manifest,
                        projectionSupplement: supplement,
                        targetRootURL: request.targetRootURL
                    )
                } catch {
                    throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
                }
            case .liveSource(let sourceURL):
                do {
                    let projection = try capacityProbe.conservativeProjectedBytes(
                        sourceURL: sourceURL,
                        targetRootURL: request.targetRootURL
                    )
                    projectedCopyBytes = max(projection, request.minimumProjectedBytes)
                } catch {
                    throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
                }
            case .minimum:
                do {
                    projectedCopyBytes = try capacityProbe.conservativeProjectedBytes(
                        minimumBytes: request.minimumProjectedBytes,
                        targetRootURL: request.targetRootURL
                    )
                } catch {
                    throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
                }
            }
            let availableCapacityBytes: Int64
            do {
                // Capacity is deliberately sampled after the potentially long
                // projection so it is the last filesystem snapshot before policy.
                availableCapacityBytes = try capacityProbe.availableCapacityBytes(
                    at: request.targetRootURL
                )
            } catch {
                throw VaultWriteAdmissionError.postponed(.archiveCapacityUnavailable)
            }
            let currentSettings: AppSettings
            do {
                // Reload the user floor after projection and capacity sampling;
                // stale policy must never authorize the enclosed mutation.
                currentSettings = try settingsStore.loadSettings()
            } catch {
                throw VaultWriteAdmissionError.postponed(.invalidPolicy)
            }
            if let reason = VaultArchiveWriteAdmissionEvaluator().postponement(
                availableCapacityBytes: availableCapacityBytes,
                projectedCopyBytes: projectedCopyBytes,
                minimumFreeSpaceGiB: currentSettings.vault.transferFreeSpaceReserveGiB
            ) {
                throw VaultWriteAdmissionError.postponed(reason)
            }
            try await operation()
        }
    }

    func makeRemovalAdmission(song: Song, trigger: ProjectVaultArchiveTrigger) -> LocalVaultTransferEngine.RemovalAdmission {
        let settingsStore = self.settingsStore
        let activityProbe = self.activityProbe
        let now = self.now
        let songID = song.id
        return { record in
            let settings = try settingsStore.loadSettings()
            guard !settings.vault.automationEmergencyStop else {
                throw ProjectVaultRuntimeError.emergencyStop
            }
            guard settings.vault.isEnabled else { throw ProjectVaultRuntimeError.disabled }
            if trigger == .manual {
                guard settings.vault.independentBackupConfirmed else {
                    throw ProjectVaultRuntimeError.independentBackupRequired
                }
            } else {
                guard ProjectVaultRolloutPolicy.permitsActiveCopyRemoval(settings.vault) else {
                    throw ProjectVaultRuntimeError.automaticArchivingDisabled
                }
            }
            let keepLocalKeys = Set([
                songID,
                record.projectID.description,
                record.sourceURL.standardizedFileURL.path,
                record.sourceURL.standardizedFileURL.resolvingSymlinksInPath().path,
            ])
            guard settings.vault.keepLocalProjectIDs.isDisjoint(with: keepLocalKeys) else {
                throw ProjectVaultRuntimeError.keepLocal
            }
            try await Self.requireProjectIdle(activityProbe, in: record.sourceURL)
            // Explicit archiving may follow a save immediately. The engine still
            // re-verifies Source and Archive bytes after the final open-file probe.
            if trigger == .manual { return }
            switch await activityProbe.writeActivityStatus(
                in: record.sourceURL,
                since: now().addingTimeInterval(-10 * 60)
            ) {
            case .clear: return
            case .busy: throw ProjectVaultRuntimeError.activityPostponed(.recentWriteActivity)
            case .uncertain(let reason): throw ProjectVaultRuntimeError.activityPostponed(.uncertainActivity(reason))
            }
        }
    }

    /// Refuses while a DAW or another program holds the project. An uncertain
    /// probe is reported as uncertainty, never as a confirmed DAW or open-file hit,
    /// so the user is not told to close a DAW that may not be running.
    static func requireProjectIdle(
        _ activityProbe: any VaultAutomationActivityProbing,
        in sourceURL: URL
    ) async throws {
        switch await activityProbe.cubaseStatus() {
        case .clear: break
        case .busy: throw ProjectVaultRuntimeError.activityPostponed(.cubaseRunning)
        case .uncertain(let reason): throw ProjectVaultRuntimeError.activityPostponed(.uncertainActivity(reason))
        }
        switch await activityProbe.openFileStatus(in: sourceURL) {
        case .clear: break
        case .busy: throw ProjectVaultRuntimeError.activityPostponed(.openFiles)
        case .uncertain(let reason): throw ProjectVaultRuntimeError.activityPostponed(.uncertainActivity(reason))
        }
    }
}
