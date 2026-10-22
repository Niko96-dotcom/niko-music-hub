import Foundation
import NikoMusicCore

/// The one way a tool admits an output folder: the WAV Converter, Downloader, Recorder,
/// Stem Separation and the Settings output picker.
///
/// It is built from an `AppSettings` snapshot only, so the protected roots are always
/// every configured music root, whatever its role, enabled state or the Vault switch
/// (`AppSettings.outputProtectedRoots`). Writers that chose their own list protected the
/// browse list (604025d) or nothing at all after a `try? … ?? .default` settings load
/// (e2135e6). Load the snapshot with `try settingsStore.loadSettings()` and refuse the
/// write when it throws. `OutputGuardSourceTests` fails on `OutputWriteGuard` used
/// anywhere else in the app.
public struct ToolOutputGuard: Equatable, Sendable {
    let protectedRoots: [URL]

    /// Each root's stored path and, when it has a bookmark, where the bookmark points now
    /// (stale or not), so a root renamed or moved in Finder stays protected.
    public init(
        settings: AppSettings,
        bookmarks: any SecurityScopedBookmarkResolving = FoundationSecurityScopedBookmarks()
    ) {
        var roots = settings.outputProtectedRoots
        for root in settings.musicRoots {
            if let bookmark = root.securityScopedBookmark,
               let current = bookmarks.currentLocation(ofBookmark: bookmark) {
                roots.append(current)
            }
        }
        protectedRoots = roots
    }

    /// Throws `OutputWriteGuardError.outputInsideArchiveRoot` when `folder`, or what it
    /// resolves to, is a protected root or inside one.
    public func validate(_ folder: URL) throws {
        try OutputWriteGuard().validateCanWriteOutput(to: folder, archiveRoots: protectedRoots)
    }
}
