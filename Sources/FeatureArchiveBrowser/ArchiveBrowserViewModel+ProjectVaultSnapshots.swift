import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    /// O(1) snapshot lookup. Owned by `ArchiveVaultObservation`.
    func projectVaultSnapshot(for song: Song) -> ProjectVaultRuntimeSnapshot? {
        vaultObservation.snapshot(for: song)
    }

    /// Caches one live snapshot through the observation owner. Index-only;
    /// callers rebuild cards explicitly to stay coalesced.
    func cacheProjectVaultSnapshot(_ snapshot: ProjectVaultRuntimeSnapshot) {
        vaultObservation.cache(snapshot)
    }

    /// Linked-archive validation. Owned by the observation; thin delegate here
    /// preserves existing callers with no duplicate logic.
    func linkedArchive(for snapshot: ProjectVaultRuntimeSnapshot) -> ProjectVaultLinkedArchive? {
        vaultObservation.linkedArchive(for: snapshot)
    }

    /// Canonical path for Vault lookups. Owned by the observation; thin
    /// delegate here preserves existing callers (`+ProjectVaultActions`,
    /// `+ProjectVaultRestore`, `+ProjectVaultIdentityReview`).
    static func vaultCanonicalPath(_ url: URL) -> String {
        ArchiveVaultObservation.vaultCanonicalPath(url)
    }
}
