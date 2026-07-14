#if DEBUG
import AppCore
import Foundation
import NikoMusicCore

enum BookmarkRelaunchProofCommands {
    static func runIfRequested() -> Bool {
        let runtime = MusicHubRuntimeEnvironment.current
        guard let mode = runtime.bookmarkProofMode else { return false }

        do {
            guard runtime.usesIsolatedSettingsSuite,
                  let suiteName = runtime.settingsSuiteName,
                  let defaults = UserDefaults(suiteName: suiteName),
                  let activeURL = runtime.bookmarkProofActiveRootURL,
                  let archiveURL = runtime.bookmarkProofArchiveRootURL else {
                throw ProofError.requiresIsolatedSuiteAndRoots
            }

            let store = UserDefaultsSettingsStore(userDefaults: defaults)
            switch mode {
            case "seed":
                var settings = try store.loadSettings()
                let manager = VaultRootManager()
                settings = try manager.replacingRoot(role: .active, with: activeURL, in: settings)
                settings = try manager.replacingRoot(role: .archive, with: archiveURL, in: settings)
                try store.saveSettings(settings)
                print("[bookmark-relaunch-proof] seeded")
            case "verify":
                let settings = try store.loadSettings()
                try verify(settings: settings, activeURL: activeURL, archiveURL: archiveURL)
                print("[bookmark-relaunch-proof] verified")
            default:
                throw ProofError.unsupportedMode(mode)
            }
            fflush(stdout)
            exit(0)
        } catch {
            fputs("bookmark relaunch proof failed: \(error)\n", stderr)
            fflush(stderr)
            exit(1)
        }
    }

    private static func verify(settings: AppSettings, activeURL: URL, archiveURL: URL) throws {
        let validator = MusicRootValidator()
        let resolver = FoundationSecurityScopedBookmarks()
        let expected: [(MusicRootRole, URL, UUID?)] = [
            (.active, activeURL, settings.vault.activeRootID),
            (.archive, archiveURL, settings.vault.archiveRootID),
        ]

        for (role, expectedURL, selectedID) in expected {
            guard let selectedID,
                  let root = settings.musicRoots.first(where: { $0.id == selectedID && $0.role == role }),
                  root.securityScopedBookmark != nil else {
                throw ProofError.missingPersistedRoot(role)
            }
            let resolved = try root.resolvedURL(using: resolver)
            guard validator.canonicalURL(for: resolved) == validator.canonicalURL(for: expectedURL) else {
                throw ProofError.resolvedPathMismatch(role)
            }
            _ = SecurityScopedRootAccess(url: resolved)
        }
    }
}

private enum ProofError: Error {
    case requiresIsolatedSuiteAndRoots
    case unsupportedMode(String)
    case missingPersistedRoot(MusicRootRole)
    case resolvedPathMismatch(MusicRootRole)
}
#endif
