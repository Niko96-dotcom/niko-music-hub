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
    let keepLocalProjectIDs: Set<String>

    init?(settings: AppSettings) {
        guard settings.vault.isEnabled else { return nil }
        activeRoot = settings.musicRoots.first { $0.id == settings.vault.activeRootID }
        archiveRoot = settings.musicRoots.first { $0.id == settings.vault.archiveRootID }
        generationReviewResolver = ProjectVaultGenerationReviewResolver(settings: settings)
        keepLocalProjectIDs = settings.vault.keepLocalProjectIDs
    }
}
