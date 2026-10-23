import Foundation
import NikoMusicCore

/// The folders the Archive Browser scans, as stored in settings: which stored
/// roots it scans, and the two edits a person makes (add a folder, remove a
/// folder). Edits change settings only, never a file. A record an edit does not
/// name keeps its place, ID and bookmark: Vault roots, disabled records, roots
/// whose access failed, the Vault archive binding.
///
/// Folders are matched by canonical path (`/tmp` and `/private/tmp` are one
/// folder) and, for a record with a bookmark, by where the bookmark points now,
/// so a moved folder still matches its record.
public struct ArchiveScanList: Sendable {
    private let bookmarks: any SecurityScopedBookmarkResolving

    public init(bookmarks: any SecurityScopedBookmarkResolving = FoundationSecurityScopedBookmarks()) {
        self.bookmarks = bookmarks
    }

    /// The stored roots the archive scans, in stored order: `effectiveScanRoots`
    /// without the Vault Archive root while Vault is on.
    public static func scannedRoots(in settings: AppSettings) -> [StoredMusicRoot] {
        settings.effectiveScanRoots.filter { root in
            !(settings.vault.isEnabled && root.id == settings.vault.archiveRootID)
        }
    }

    /// One spelling per folder: symlinks resolved, so `/tmp` and `/private/tmp`
    /// (or `/var` and `/private/var`) compare equal.
    public static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Adds `folder`, with `bookmark` when one could be made, and marks archive
    /// onboarding done.
    ///
    /// - The folder of the scanned Vault Active root repairs that root in place
    ///   (same ID, role and name, new bookmark) and drops enabled Scan-only
    ///   duplicates of it. A different folder never rebinds a Vault root.
    /// - A folder already on the list keeps its record and gets the new bookmark.
    /// - Any other folder becomes a new Scan-only record. A disabled record of
    ///   the same folder stays as it is.
    public func adding(_ folder: URL, bookmark: Data?, to settings: AppSettings) -> AppSettings {
        var settings = settings
        settings.archiveOnboardingCompleted = true
        let canonical = Self.canonicalPath(for: folder)

        if let vaultIndex = settings.musicRoots.firstIndex(where: { root in
            root.role != .scanOnly && Self.isScannedVaultRoot(root, in: settings)
                && Self.canonicalPath(for: root.fallbackURL) == canonical
        }) {
            if let bookmark {
                settings.musicRoots[vaultIndex].securityScopedBookmark = bookmark
            }
            settings.musicRoots.removeAll { root in
                root.role == .scanOnly && root.isEnabled && Self.canonicalPath(for: root.fallbackURL) == canonical
            }
            return settings
        }

        if let listedIndex = settings.musicRoots.firstIndex(where: { root in
            root.role == .scanOnly && root.isEnabled && matches(root, canonical: canonical)
        }) {
            if let bookmark {
                settings.musicRoots[listedIndex].securityScopedBookmark = bookmark
            }
            return settings
        }

        settings.musicRoots.append(
            StoredMusicRoot(role: .scanOnly, url: folder.standardizedFileURL, securityScopedBookmark: bookmark)
        )
        return settings
    }

    /// Removes `folder` from the scan list: every enabled Scan-only record of
    /// it, including one whose access failed. A Vault root is changed in the
    /// Project Vault pane, not here, and the Vault archive binding stays while
    /// Vault is on.
    public func removing(_ folder: URL, from settings: AppSettings) -> AppSettings {
        var settings = settings
        let canonical = Self.canonicalPath(for: folder)
        settings.musicRoots.removeAll { root in
            root.role == .scanOnly
                && root.isEnabled
                && !(settings.vault.isEnabled && root.id == settings.vault.archiveRootID)
                && matches(root, canonical: canonical)
        }
        return settings
    }

    /// A Vault-role root that the archive scans in place of a Scan-only record:
    /// Vault on, the root enabled, and not the Vault Archive root.
    private static func isScannedVaultRoot(_ root: StoredMusicRoot, in settings: AppSettings) -> Bool {
        settings.vault.isEnabled && root.isEnabled && root.id != settings.vault.archiveRootID
    }

    private func matches(_ root: StoredMusicRoot, canonical: String) -> Bool {
        if Self.canonicalPath(for: root.fallbackURL) == canonical { return true }
        guard let bookmark = root.securityScopedBookmark,
              let resolved = try? bookmarks.resolveBookmark(bookmark)
        else { return false }
        return Self.canonicalPath(for: resolved) == canonical
    }
}
