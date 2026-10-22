import AppCore
import Foundation
import NikoMusicCore

/// The small, immutable subset of settings that determines Project Vault card
/// state. It is loaded once while refreshing the presentation cache, never from
/// a SwiftUI card render.
struct ProjectVaultPresentationContext: Equatable {
    let activeRoot: StoredMusicRoot?
    let archiveRoot: StoredMusicRoot?
    let generationReviewResolver: ProjectVaultGenerationReviewResolver?
    let keepLocalPins: KeepLocalPins
    /// Whether the live settings currently allow offering "Ready to free
    /// space": exactly the Done/manual removal gate
    /// (`permitsUserInitiatedRemoval` — user-initiated archiving base with a
    /// non-disabled rollout and both roots, plus an explicit free-space intent
    /// and the independent-backup acknowledgement, but not the background
    /// scheduler opt-in). A copy-only preference, Keep Local (per song,
    /// checked at the card), or a pause never presents free-space as already
    /// authorized; the offer itself still routes through a fresh confirmation
    /// that rechecks every gate at execution.
    let allowsFreeSpaceOffer: Bool
    /// Both Vault folders are chosen, enabled and of the right role: the gate
    /// the runtime's configuration applies before any capture or archive.
    /// Without it nothing can reach the Vault, so Done stays a plain status
    /// change instead of a capture that only fails.
    let rootsConfigured: Bool

    init?(settings: AppSettings) {
        guard settings.vault.isEnabled else { return nil }
        activeRoot = settings.musicRoots.first { $0.id == settings.vault.activeRootID }
        archiveRoot = settings.musicRoots.first { $0.id == settings.vault.archiveRootID }
        generationReviewResolver = ProjectVaultGenerationReviewResolver(settings: settings)
        keepLocalPins = settings.vault.keepLocalPins
        allowsFreeSpaceOffer = ProjectVaultRolloutPolicy.permitsUserInitiatedRemoval(settings.vault)
        rootsConfigured = KeepLocalReviewPolicy.vaultRootsConfigured(in: settings)
    }
}
