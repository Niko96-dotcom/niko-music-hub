#if DEBUG
import AppCore
import Foundation
import NikoMusicCore
import OSLog

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
            case "seed", "seed-vault-gui":
                var settings = try store.loadSettings()
                let manager = VaultRootManager()
                settings = try manager.replacingRoot(role: .active, with: activeURL, in: settings)
                settings = try manager.replacingRoot(role: .archive, with: archiveURL, in: settings)
                if mode == "seed-vault-gui" {
                    // Friends-stage vault ready for GUI Accept (NMH-138/139). No live Music roots.
                    settings.vault.isEnabled = true
                    settings.vault.rolloutStage = .friends
                    settings.vault.independentBackupConfirmed = true
                    settings.vault.automaticArchiving = false
                    settings.vault.automationEmergencyStop = false
                    settings.vault.transferFreeSpaceReserveGiB = 1
                    // Keep archive browser pointed at the fixture Active root only.
                    settings.archiveOnboardingCompleted = true
                }
                try store.saveSettings(settings)
                // Stdout is the proof contract (script/prove-bookmark-relaunch.sh greps it); keep it.
                print(mode == "seed-vault-gui" ? "[bookmark-relaunch-proof] seeded-vault-gui" : "[bookmark-relaunch-proof] seeded")
                HubLogging.logger(category: .vault).info("Bookmark proof seeded")
            case "verify":
                let settings = try store.loadSettings()
                try verify(settings: settings, activeURL: activeURL, archiveURL: archiveURL)
                // Stdout is the proof contract; keep it.
                print("[bookmark-relaunch-proof] verified")
                HubLogging.logger(category: .vault).info("Bookmark proof verified")
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
