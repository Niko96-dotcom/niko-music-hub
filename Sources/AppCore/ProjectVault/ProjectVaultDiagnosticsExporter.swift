import Foundation

public enum ProjectVaultDiagnosticsExportError: Error, Equatable, Sendable {
    case destinationInsideMusicRoot
}

public enum ProjectVaultDiagnosticsExporter {
    public static func formattedText(settings: AppSettings, health: ProjectVaultHealth) -> String {
        let iso = ISO8601DateFormatter()
        let vault = settings.vault
        let active = settings.musicRoots.first { $0.id == vault.activeRootID && $0.role == .active }
        let archive = settings.musicRoots.first { $0.id == vault.archiveRootID && $0.role == .archive }
        return [
            "Niko Music Hub — Project Vault diagnostics",
            "enabled=\(vault.isEnabled)",
            "rollout_stage=\(vault.rolloutStage.rawValue)",
            "automatic_archiving=\(vault.automaticArchiving)",
            "emergency_stop=\(vault.automationEmergencyStop)",
            "automation_permitted=\(ProjectVaultRolloutPolicy.permitsAutomaticArchiving(vault))",
            "active_root_configured=\(active != nil)",
            "archive_root_configured=\(archive != nil)",
            "provider_status=\(health.providerStatus.rawValue)",
            "independent_backup_confirmed=\(vault.independentBackupConfirmed)",
            "last_successful_verification=\(vault.lastSuccessfulVerificationAt.map(iso.string(from:)) ?? "never")",
            "last_restore_drill=\(vault.lastRestoreDrillAt.map(iso.string(from:)) ?? "never")",
            "inactivity_days=\(vault.inactivityDays)",
            "minimum_free_space_gib=\(vault.minimumFreeSpaceGiB)",
            "keep_previous_generation_days=\(vault.keepPreviousGenerationDays)",
            "keep_local_projects=\(vault.keepLocalProjectIDs.count)",
            "note=No absolute music paths or bookmark data are included."
        ].joined(separator: "\n") + "\n"
    }

    public static func export(settings: AppSettings, health: ProjectVaultHealth, to destination: URL) throws {
        let candidate = destination.standardizedFileURL.resolvingSymlinksInPath()
        for root in settings.musicRoots {
            let rootURL = root.fallbackURL.standardizedFileURL.resolvingSymlinksInPath()
            if candidate.path == rootURL.path || candidate.path.hasPrefix(rootURL.path + "/") {
                throw ProjectVaultDiagnosticsExportError.destinationInsideMusicRoot
            }
        }
        try formattedText(settings: settings, health: health).write(to: destination, atomically: true, encoding: .utf8)
    }
}
