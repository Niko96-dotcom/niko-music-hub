import Foundation
import NikoMusicCore

public enum VaultRootManagerError: Error, Equatable, Sendable {
    case unsupportedRole(MusicRootRole)
    case missingCompanionRoot(MusicRootRole)
}

public struct VaultRootManager: Sendable {
    private let bookmarks: any SecurityScopedBookmarkProviding
    private let validator: MusicRootValidator

    public init(
        bookmarks: any SecurityScopedBookmarkProviding = FoundationSecurityScopedBookmarks(),
        validator: MusicRootValidator = MusicRootValidator()
    ) {
        self.bookmarks = bookmarks
        self.validator = validator
    }

    /// Replaces settings metadata only. It deliberately performs no file operation.
    /// Once both Vault roles are present, the pair is canonicalized and validated before
    /// either selection is committed to the returned settings value.
    public func replacingRoot(
        role: MusicRootRole,
        with url: URL,
        in settings: AppSettings
    ) throws -> AppSettings {
        guard role == .active || role == .archive else {
            throw VaultRootManagerError.unsupportedRole(role)
        }

        let canonicalURL = try validator.validateCandidate(url)
        let bookmark = try bookmarks.makeBookmark(for: canonicalURL)
        let replacement = StoredMusicRoot(
            role: role,
            url: canonicalURL,
            securityScopedBookmark: bookmark
        )

        var candidate = settings
        candidate.musicRoots.removeAll { $0.role == role }
        candidate.musicRoots.append(replacement)
        switch role {
        case .active:
            candidate.vault.activeRootID = replacement.id
        case .archive:
            candidate.vault.archiveRootID = replacement.id
        case .scanOnly:
            break
        }

        let active = candidate.musicRoots.first { $0.id == candidate.vault.activeRootID && $0.role == .active }
        let archive = candidate.musicRoots.first { $0.id == candidate.vault.archiveRootID && $0.role == .archive }
        if let active, let archive {
            try validator.validate(activeRoot: active.fallbackURL, archiveRoot: archive.fallbackURL)
        }
        return candidate
    }
}
