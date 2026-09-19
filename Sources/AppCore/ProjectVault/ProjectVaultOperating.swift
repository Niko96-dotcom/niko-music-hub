import Foundation
import NikoMusicCore

public enum ProjectVaultArchiveTrigger: String, Codable, Sendable {
    case manual
    case backupCopy
    case workflowDone
}

public protocol ProjectVaultOperating: Sendable {
    func restoreOptions(snapshot: ProjectVaultRuntimeSnapshot) async throws -> ProjectVaultRestoreOptions?
    func restoreAndOpen(snapshot: ProjectVaultRuntimeSnapshot, selectedProjectRelativePath: String?, destinationRelativePath: String?) async throws -> VaultRestoreRecord
    func restoreProgress(for projectID: ProjectID) async -> ProjectVaultRestoreProgress?
    func snapshots() async throws -> [ProjectVaultRuntimeSnapshot]
    /// Compatibility copy-only entry point. It always preserves the Active
    /// copy and never authorizes removal — not for `.manual`, and not for
    /// `.workflowDone` even when live settings would otherwise permit it.
    /// Choice: inferring destructive approval from the trigger (manual) or
    /// from live settings (automatic Done) would let a stale caller, a timer
    /// retry, or a relaunch delete without a bound per-operation confirmation.
    /// Callers that intend removal must capture an explicit
    /// `ProjectVaultArchiveAuthorization` and call
    /// `archive(song:trigger:authorization:)`. Automatic copies keep working
    /// through this method; only deletion requires the bound value.
    func archive(song: Song, trigger: ProjectVaultArchiveTrigger) async throws -> ProjectVaultRuntimeSnapshot
    /// Bound execution entry point (frozen V3 API). The passed authorization
    /// must have been captured at confirmation/intent time; a value minted
    /// inside execution cannot substitute for it. The runtime revalidates the
    /// bound source path/object, song/catalog identity, roots (IDs and paths),
    /// trigger, and destructiveness ceiling against live state after awaits
    /// and immediately before removal. Live settings may only restrict.
    func archive(song: Song, trigger: ProjectVaultArchiveTrigger, authorization: ProjectVaultArchiveAuthorization) async throws -> ProjectVaultRuntimeSnapshot
    /// Capture API usable before confirmation (no mutation lease, no transfer).
    /// Binds source path + filesystem object, song/catalog identity where
    /// known, current root IDs + paths, trigger, and the requested
    /// destructiveness ceiling. Never binds titles. Throws when the request
    /// itself is invalid (for example removal requested for `.backupCopy`, or
    /// stable live gates already forbid removal). Volatile activity probes are
    /// checked at execution, not here. Async so actor runtimes can bind live
    /// state without bypassing isolation.
    func captureArchiveAuthorization(
        for song: Song,
        trigger: ProjectVaultArchiveTrigger,
        removingActiveCopy: Bool,
        catalogProjectID: ProjectID?
    ) async throws -> ProjectVaultArchiveAuthorization
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

    func captureArchiveAuthorization(
        for song: Song,
        trigger: ProjectVaultArchiveTrigger,
        removingActiveCopy: Bool,
        catalogProjectID: ProjectID?
    ) async throws -> ProjectVaultArchiveAuthorization {
        throw ProjectVaultAuthorizationError.authorizationRequired
    }

    func archive(song: Song, trigger: ProjectVaultArchiveTrigger, authorization: ProjectVaultArchiveAuthorization) async throws -> ProjectVaultRuntimeSnapshot {
        guard authorization.trigger == trigger,
              authorization.songID == song.id,
              authorization.maximumDestructiveness == .copyOnly else {
            throw ProjectVaultAuthorizationError.removalNotAuthorized
        }
        return try await archive(song: song, trigger: trigger)
    }
}
