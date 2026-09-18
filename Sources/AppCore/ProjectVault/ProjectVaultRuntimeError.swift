import Darwin
import Foundation
import NikoMusicCore

public enum ProjectVaultRuntimeError: Error, LocalizedError, Equatable {
    case unavailable
    case rootUnavailable(MusicRootRole)
    case disabled
    case automaticArchivingDisabled
    case independentBackupRequired
    case emergencyStop
    case keepLocal
    case mutationInProgress
    case mutationLockUnavailable(Int32)
    case transferOwned
    case activityPostponed(VaultAutomationPostponement)
    case archiveFailed(String)
    case noVerifiedArchive
    /// The project folder is not present in Active Projects; nothing was recorded.
    case sourceUnavailable(title: String)
    /// The project folder could not be read completely; nothing was recorded.
    case sourceInventoryIncomplete(title: String, reason: String)
    /// The catalog cannot say which entry this project is; nothing was recorded.
    case identityAmbiguous(title: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Project Vault needs valid Active Projects and Archive roots."
        case .rootUnavailable(let role): "The \(role == .active ? "Active Projects" : "Archive / Vault") folder is unavailable. Reconnect its drive or choose the folder again in Project Vault settings, then retry."
        case .disabled: "Project Vault is disabled."
        case .automaticArchivingDisabled: "Automatic archiving is disabled."
        case .independentBackupRequired: "Protect the Archive with an independent backup and confirm it in Project Vault settings before removing the Active copy. Use Create Backup Copy to keep the project local."
        case .emergencyStop: "Project Vault Emergency Stop is on."
        case .keepLocal: "Turn off Keep Local before archiving this project."
        case .mutationInProgress: "Another Project Vault operation is already in progress."
        case .mutationLockUnavailable(let code): "Project Vault cannot access its operation lock: \(String(cString: strerror(code))). Check access to the app data folder and retry."
        case .transferOwned: "This project already has a Project Vault transfer that must finish or be reviewed."
        case .activityPostponed(.cubaseRunning): "Archiving is paused while Cubase or Ableton Live is running. Close the DAW and retry."
        case .activityPostponed(.openFiles): "A program still has files open in this project. Close those files and retry. The Active copy was kept."
        case .activityPostponed(let reason): reason.message
        case .archiveFailed(let reason): "Archiving stopped safely: \(reason)."
        case .noVerifiedArchive: "No verified archive generation is available."
        case .sourceUnavailable(let title): "The project folder for “\(title)” is not available in Active Projects. Rescan the archive, then retry. Nothing was changed."
        case .sourceInventoryIncomplete(let title, let reason): "Project Vault could not read every project file for “\(title)”: \(reason). Rescan the archive, then retry. Nothing was changed."
        case .identityAmbiguous(let title, let reason): "Project Vault cannot tell whether “\(title)” is the same project as an existing catalog entry. \(reason) Choose Link if these are the same project. Choose Keep Separate if they are different projects. Nothing is archived until you choose."
        }
    }
}
