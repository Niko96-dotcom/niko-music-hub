import Darwin
import Foundation
import NikoMusicCore

// MARK: - V3 bound-operation authorization (runtime half, frozen API)
//
// An explicit, immutable authorization captured at confirmation/intent binds
// one operation to one filesystem object. The UI consumer captures it before
// showing confirmation, passes the same value through confirmation, queue,
// and retries, and hands it to the execution API.
//
// Bound identity (titles are display-only and never consulted):
// - source canonical path AND source filesystem object (device + inode).
// - song ID (`Song.id`, path-derived) and catalog `ProjectID` where known.
// - active/archive root IDs, canonical paths, AND root filesystem objects, so
//   a re-pointed root (same UUID, new path) or a same-path root replacement
//   (same path, new device/inode) is a mismatch.
// - trigger and maximum permitted destructiveness.
// - `authorizedAt` is an ordering guard only: values dated after execution
//   start are rejected. It does not prove where a value was minted; the
//   execution API only validates the passed value against live state.
//
// Live restriction (never escalation):
// - `backupCopy` is always copy-only; removal for it is refused outright.
// - Removal additionally requires live settings at removal time (enabled, no
//   Emergency Stop, trigger-appropriate backup/rollout gate, Keep Local
//   disjoint) and a clear final activity/idle probe. Any change during awaits
//   denies removal; the bound admission rechecks everything after its final
//   await, immediately before the engine's synchronous remove.
// - A copy-only authorization never deletes, however permissive live settings
//   become.
//
// Automatic Done contract: without a bound per-operation authorization whose
// maximum is `.mayRemoveActiveCopy`, Done archiving is a verified copy only
// (`archiveVerified`) and leaves the Active copy in place. Neither a Done
// status, a relaunch, nor permissive settings imply destructive approval.

public enum ProjectVaultArchiveDestructiveness: String, Codable, Sendable, Equatable, CaseIterable {
    case copyOnly
    case mayRemoveActiveCopy
}

public struct ProjectVaultSourceFileSystemIdentity: Codable, Sendable, Hashable, Equatable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

public struct ProjectVaultArchiveAuthorization: Codable, Sendable, Equatable {
    public let sourceCanonicalPath: String
    public let sourceFileSystemIdentity: ProjectVaultSourceFileSystemIdentity
    public let songID: String
    public let catalogProjectID: ProjectID?
    public let activeRootID: UUID
    public let activeRootCanonicalPath: String
    public let activeRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity
    public let archiveRootID: UUID
    public let archiveRootCanonicalPath: String
    public let archiveRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity
    public let trigger: ProjectVaultArchiveTrigger
    public let maximumDestructiveness: ProjectVaultArchiveDestructiveness
    public let authorizedAt: Date

    public init(
        sourceCanonicalPath: String,
        sourceFileSystemIdentity: ProjectVaultSourceFileSystemIdentity,
        songID: String,
        catalogProjectID: ProjectID?,
        activeRootID: UUID,
        activeRootCanonicalPath: String,
        activeRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity,
        archiveRootID: UUID,
        archiveRootCanonicalPath: String,
        archiveRootFileSystemIdentity: ProjectVaultSourceFileSystemIdentity,
        trigger: ProjectVaultArchiveTrigger,
        maximumDestructiveness: ProjectVaultArchiveDestructiveness,
        authorizedAt: Date
    ) {
        self.sourceCanonicalPath = sourceCanonicalPath
        self.sourceFileSystemIdentity = sourceFileSystemIdentity
        self.songID = songID
        self.catalogProjectID = catalogProjectID
        self.activeRootID = activeRootID
        self.activeRootCanonicalPath = activeRootCanonicalPath
        self.activeRootFileSystemIdentity = activeRootFileSystemIdentity
        self.archiveRootID = archiveRootID
        self.archiveRootCanonicalPath = archiveRootCanonicalPath
        self.archiveRootFileSystemIdentity = archiveRootFileSystemIdentity
        self.trigger = trigger
        self.maximumDestructiveness = maximumDestructiveness
        self.authorizedAt = authorizedAt
    }

    public var permitsRemoval: Bool {
        maximumDestructiveness == .mayRemoveActiveCopy
    }

    /// Returns the SAME bound operation downgraded to copy-only. Every binding
    /// field — source path and filesystem object, song/catalog identity, both
    /// root IDs/paths/objects, trigger, and `authorizedAt` — is preserved, so
    /// the value still authorizes exactly the same operation and still fails
    /// closed on any drift; only the destructiveness ceiling is lowered.
    /// Delayed automatic retries and recovery/relaunch paths use this so a
    /// destructive approval is never reused: no new removal token is minted,
    /// and validation is unchanged (a copy-only value never deletes, however
    /// permissive live settings become).
    public func downgradedToCopyOnly() -> ProjectVaultArchiveAuthorization {
        ProjectVaultArchiveAuthorization(
            sourceCanonicalPath: sourceCanonicalPath,
            sourceFileSystemIdentity: sourceFileSystemIdentity,
            songID: songID,
            catalogProjectID: catalogProjectID,
            activeRootID: activeRootID,
            activeRootCanonicalPath: activeRootCanonicalPath,
            activeRootFileSystemIdentity: activeRootFileSystemIdentity,
            archiveRootID: archiveRootID,
            archiveRootCanonicalPath: archiveRootCanonicalPath,
            archiveRootFileSystemIdentity: archiveRootFileSystemIdentity,
            trigger: trigger,
            maximumDestructiveness: .copyOnly,
            authorizedAt: authorizedAt
        )
    }

    public static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Filesystem object identity of the directory itself. Uses `fstatat` (following
    /// a final symlink, consistent with `canonicalPath`) so a root configured
    /// through a Finder alias observes the actual storage directory; a
    /// re-pointed alias still mismatches via its canonical path, and a
    /// replaced target still mismatches via its device/inode.
    public static func fileSystemIdentity(at url: URL) throws -> ProjectVaultSourceFileSystemIdentity {
        var information = stat()
        let result = url.path.withCString { Darwin.fstatat(AT_FDCWD, $0, &information, 0) }
        guard result == 0,
              (information.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw ProjectVaultAuthorizationError.sourceIdentityMismatch
        }
        return ProjectVaultSourceFileSystemIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }

    /// Resolves the live Active/Archive root IDs, canonical paths, and root
    /// filesystem objects from settings without actor isolation, for use
    /// inside `@Sendable` admission callbacks. Throws `unavailable` when the
    /// configuration itself is invalid, or `rootUnavailable` when a root
    /// folder cannot be observed; callers compare the result to the bound
    /// value and throw `rootMismatch` on any difference (including a path
    /// change with an unchanged UUID, or a same-path replacement with new
    /// device/inode).
    public static func currentRoots(from settings: AppSettings) throws -> (
        activeID: UUID,
        activePath: String,
        activeIdentity: ProjectVaultSourceFileSystemIdentity,
        archiveID: UUID,
        archivePath: String,
        archiveIdentity: ProjectVaultSourceFileSystemIdentity
    ) {
        guard settings.vault.isEnabled,
              let activeID = settings.vault.activeRootID,
              let archiveID = settings.vault.archiveRootID,
              let active = settings.musicRoots.first(where: { $0.id == activeID && $0.role == .active && $0.isEnabled }),
              let archive = settings.musicRoots.first(where: { $0.id == archiveID && $0.role == .archive && $0.isEnabled }) else {
            throw ProjectVaultRuntimeError.unavailable
        }
        let resolver = FoundationSecurityScopedBookmarks()
        let activeURL: URL
        let archiveURL: URL
        do {
            activeURL = try active.resolvedURL(using: resolver)
        } catch {
            throw ProjectVaultRuntimeError.rootUnavailable(.active)
        }
        do {
            archiveURL = try archive.resolvedURL(using: resolver)
        } catch {
            throw ProjectVaultRuntimeError.rootUnavailable(.archive)
        }
        let activeIdentity: ProjectVaultSourceFileSystemIdentity
        do {
            activeIdentity = try fileSystemIdentity(at: activeURL)
        } catch {
            throw ProjectVaultRuntimeError.rootUnavailable(.active)
        }
        let archiveIdentity: ProjectVaultSourceFileSystemIdentity
        do {
            archiveIdentity = try fileSystemIdentity(at: archiveURL)
        } catch {
            throw ProjectVaultRuntimeError.rootUnavailable(.archive)
        }
        return (
            activeID,
            canonicalPath(for: activeURL),
            activeIdentity,
            archiveID,
            canonicalPath(for: archiveURL),
            archiveIdentity
        )
    }
}

public enum ProjectVaultAuthorizationError: Error, LocalizedError, Equatable, Sendable {
    case authorizationRequired
    case triggerMismatch
    case sourcePathMismatch
    case sourceIdentityMismatch
    case songMismatch
    case catalogMismatch
    case rootMismatch
    case removalNotAuthorized
    case backupCopyRemovalForbidden

    public var errorDescription: String? {
        switch self {
        case .authorizationRequired:
            "The Active folder can only be removed after you confirm. Nothing was deleted."
        case .triggerMismatch:
            "That confirmation was for a different action, so it can’t be used here. Nothing was deleted."
        case .sourcePathMismatch:
            "The project folder changed after you confirmed. Nothing was deleted."
        case .sourceIdentityMismatch:
            "The project folder was replaced after you confirmed. Nothing was deleted."
        case .songMismatch:
            "That confirmation was for a different project, so it can’t be used here. Nothing was deleted."
        case .catalogMismatch:
            "The project’s library record changed after you confirmed. Nothing was deleted."
        case .rootMismatch:
            "The Active or Archive folder setting changed after you confirmed. Nothing was deleted."
        case .removalNotAuthorized:
            "You confirmed a copy only, so the Active folder was kept."
        case .backupCopyRemovalForbidden:
            "A backup copy never removes the Active folder. It was kept."
        }
    }
}
