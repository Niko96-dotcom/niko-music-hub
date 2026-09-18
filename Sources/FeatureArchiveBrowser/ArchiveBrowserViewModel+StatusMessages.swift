import AppCore
import Foundation
import NikoMusicCore

// MARK: - Footer status message ownership

extension ArchiveBrowserViewModel {
    func setStatusMessage(_ message: String?) {
        projectVaultOwnsStatus = false
        statusBaseMessage = message
        statusMessage = combinedStatusMessage(base: message)
    }

    func setProjectVaultStatusMessage(_ message: String?) {
        projectVaultOwnsStatus = true
        statusBaseMessage = message
        statusMessage = combinedStatusMessage(base: message)
    }

    func setBackgroundStatusMessage(_ message: String?) {
        guard !projectVaultOwnsStatus else { return }
        setStatusMessage(message)
    }

    func recordPersistenceWarning(_ warning: String) {
        persistenceWarningMessage = warning
        statusMessage = combinedStatusMessage(base: statusBaseMessage)
    }

    func combinedStatusMessage(base: String?) -> String? {
        guard let persistenceWarningMessage else { return base }
        guard let base, !base.isEmpty else { return persistenceWarningMessage }
        return "\(base) \(persistenceWarningMessage)"
    }
}
