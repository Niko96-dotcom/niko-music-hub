import Foundation
import NikoMusicCore

public enum ProjectVaultArchiveTrigger: Sendable {
    case manual
    case backupCopy
    case workflowDone
}

public protocol ProjectVaultOperating: Sendable {
    func restoreOptions(snapshot: ProjectVaultRuntimeSnapshot) async throws -> ProjectVaultRestoreOptions?
    func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot, selectedProjectRelativePath: String?, destinationRelativePath: String?) async throws -> VaultRestoreRecord
    func restoreProgress(for projectID: ProjectID) async -> ProjectVaultRestoreProgress?
    func snapshots() async throws -> [ProjectVaultRuntimeSnapshot]
    func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot
    func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord
    func retryRestore(id: UUID) async throws -> VaultRestoreRecord
    func recoverInterruptedArchive(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord
    func retry(snapshot: ProjectVaultRuntimeSnapshot) async throws -> ProjectVaultRuntimeSnapshot
    func recoverAtLaunch() async
    func nextAutomaticRecoveryDate() async throws -> Date?
    func consumePendingIdentityReview() async -> ProjectIdentityReview?
}

public extension ProjectVaultOperating {
    func restoreOptions(snapshot: ProjectVaultRuntimeSnapshot) async throws -> ProjectVaultRestoreOptions? { nil }
    func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot, selectedProjectRelativePath: String?, destinationRelativePath: String?) async throws -> VaultRestoreRecord {
        guard selectedProjectRelativePath == nil, destinationRelativePath == nil else { throw ProjectVaultRuntimeError.unavailable }
        return try await restoreAndOpen(snapshot: snapshot)
    }

    func restoreProgress(for projectID: ProjectID) async -> ProjectVaultRestoreProgress? { nil }

    func recoverInterruptedArchive(snapshot: ProjectVaultRuntimeSnapshot) async throws -> VaultRestoreRecord {
        throw ProjectVaultRuntimeError.unavailable
    }

    func nextAutomaticRecoveryDate() async throws -> Date? { nil }

    func retryRestore(id: UUID) async throws -> VaultRestoreRecord {
        throw ProjectVaultRuntimeError.unavailable
    }

    func retry(snapshot: ProjectVaultRuntimeSnapshot) async throws -> ProjectVaultRuntimeSnapshot {
        throw ProjectVaultRuntimeError.unavailable
    }

    func consumePendingIdentityReview() async -> ProjectIdentityReview? { nil }
}
