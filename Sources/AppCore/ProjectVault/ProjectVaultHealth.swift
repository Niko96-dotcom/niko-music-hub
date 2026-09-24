import Foundation
import NikoMusicCore

public enum ProjectVaultProviderStatus: String, Codable, Sendable {
    case notConfigured
    case availableLocal
    case availableProvider
    case offline
}

public struct ProjectVaultHealth: Equatable, Codable, Sendable {
    public var providerStatus: ProjectVaultProviderStatus
    public var lastSuccessfulVerificationAt: Date?
    public var hasIndependentBackup: Bool

    public init(providerStatus: ProjectVaultProviderStatus, lastSuccessfulVerificationAt: Date?, hasIndependentBackup: Bool) {
        self.providerStatus = providerStatus
        self.lastSuccessfulVerificationAt = lastSuccessfulVerificationAt
        self.hasIndependentBackup = hasIndependentBackup
    }

    public var summary: String {
        switch providerStatus {
        case .notConfigured: "Choose an Archive / Vault folder to check provider health."
        case .availableLocal: "Archive folder is available locally."
        case .availableProvider: "Archive provider is online and available."
        case .offline: "Archive folder is unavailable. Automatic work is paused."
        }
    }

    public var backupWarning: String? {
        hasIndependentBackup ? nil : "Your Archive may be the only copy of these projects. Back it up somewhere else too, like Time Machine or your cloud’s version history."
    }
}

public struct ProjectVaultHealthEvaluator: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func evaluate(settings: AppSettings) -> ProjectVaultHealth {
        guard let id = settings.vault.archiveRootID,
              let root = settings.musicRoots.first(where: { $0.id == id && $0.role == .archive }) else {
            return ProjectVaultHealth(providerStatus: .notConfigured, lastSuccessfulVerificationAt: settings.vault.lastSuccessfulVerificationAt, hasIndependentBackup: settings.vault.independentBackupConfirmed)
        }
        let url = root.fallbackURL.standardizedFileURL.resolvingSymlinksInPath()
        let status: ProjectVaultProviderStatus
        if !fileManager.fileExists(atPath: url.path) || !fileManager.isReadableFile(atPath: url.path) {
            status = .offline
        } else if fileManager.isUbiquitousItem(at: url) {
            status = .availableProvider
        } else {
            status = .availableLocal
        }
        return ProjectVaultHealth(providerStatus: status, lastSuccessfulVerificationAt: settings.vault.lastSuccessfulVerificationAt, hasIndependentBackup: settings.vault.independentBackupConfirmed)
    }
}
