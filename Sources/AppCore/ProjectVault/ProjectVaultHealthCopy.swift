import Foundation

/// Sidebar copy for Project Vault provider status (NMH-057).
/// The Archive sidebar separates scan counts ("Scan Health") from vault
/// provider status ("Project Vault"). Non-offline statuses reuse
/// `ProjectVaultHealth.summary` so Settings and the sidebar never disagree.
public enum ProjectVaultHealthCopy: Sendable {
    public static let archiveSidebarOfflineLine =
        "The Project Vault disk is offline. Songs in Active stay on this Mac."

    public static func archiveSidebarLine(_ status: ProjectVaultProviderStatus) -> String {
        switch status {
        case .offline:
            archiveSidebarOfflineLine
        case .notConfigured, .availableLocal, .availableProvider:
            ProjectVaultHealth(
                providerStatus: status,
                lastSuccessfulVerificationAt: nil,
                hasIndependentBackup: false
            ).summary
        }
    }

    public static func archiveSidebarLine(_ health: ProjectVaultHealth) -> String {
        health.providerStatus == .offline ? archiveSidebarOfflineLine : health.summary
    }
}
