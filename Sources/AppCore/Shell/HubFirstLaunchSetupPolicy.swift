import Foundation

/// First-launch rule for the helper-tool Set Up sheet, decided once by the
/// composition root before any scene exists.
///
/// A returning user is anyone who already configured music folders or Project
/// Vault (even only from Settings, which never set archiveOnboardingCompleted)
/// or who already saw either onboarding flag, so the sheet also requires
/// empty music roots and a disabled Vault.
public enum HubFirstLaunchSetupPolicy {
    public static func shouldPresentSetup(store: any SettingsStore, runtimeAllowsAutoSetup: Bool) -> Bool {
        // Only a successful load counts. A missing blob loads as `.default`
        // (a brand-new install); a blob that throws belongs to a returning
        // user whose settings are damaged, who must never get the new-user
        // sheet (and whose flags cannot be written until repaired anyway).
        guard runtimeAllowsAutoSetup, let settings = try? store.loadSettings() else { return false }
        return !settings.setupAssistantShown && !settings.archiveOnboardingCompleted
            && settings.musicRoots.isEmpty && !settings.vault.isEnabled
    }
}
