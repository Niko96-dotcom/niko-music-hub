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
    /// A settings repair reset the Keep Local list, so pins may be missing.
    /// Removal stays refused until Review Keep Local clears the flag.
    case keepLocalReviewRequired
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
        case .unavailable: "Choose both Project Vault folders in Settings first."
        case .rootUnavailable(let role): "The \(role == .active ? "Active Projects" : "Archive / Vault") folder is unavailable. Reconnect its drive or choose the folder again in Project Vault settings, then retry."
        case .disabled: "Project Vault is turned off."
        case .automaticArchivingDisabled: "Automatic archiving is turned off."
        case .independentBackupRequired: "To remove the Active folder, first confirm in Project Vault settings that your Archive has its own backup. Or use Create Backup Copy to keep the project on this Mac."
        case .emergencyStop: "Project Vault Emergency Stop is on."
        case .keepLocal: "Turn off Keep Local before archiving this project."
        case .keepLocalReviewRequired: "Keep Local pins may be missing after a settings repair. Review Keep Local in Settings > Project Vault before removing the Active copy. A verified copy can still be archived."
        case .mutationInProgress: "Project Vault is already working on something. Try again when it’s done."
        case .mutationLockUnavailable(let code): "Project Vault cannot access its operation lock: \(String(cString: strerror(code))). Check access to the app data folder and retry."
        case .transferOwned: "This project already has a Vault transfer that needs to finish or be reviewed first."
        case .activityPostponed(.cubaseRunning): "Archiving is paused while Cubase or Ableton Live is running. Close the DAW and retry."
        case .activityPostponed(.openFiles): "A program still has files open in this project. Close those files and retry. The Active copy was kept."
        case .activityPostponed(let reason): reason.message
        case .archiveFailed(let reason): "Archiving stopped safely. \(reason.hasSuffix(".") ? reason : reason + ".")"
        case .noVerifiedArchive: "There’s no verified Vault copy yet."
        case .sourceUnavailable(let title): "The project folder for “\(title)” is not available in Active Projects. Rescan the archive, then retry. Nothing was changed."
        case .sourceInventoryIncomplete(let title, let reason): "Project Vault could not read every project file for “\(title)”: \(reason). Rescan the archive, then retry. Nothing was changed."
        case .identityAmbiguous(let title, let reason): "Project Vault cannot tell whether “\(title)” is the same project as one already in your library. \(reason) Choose Link if these are the same project. Choose Keep Separate if they are different projects. Nothing is archived until you choose."
        }
    }
}
