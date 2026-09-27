import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    /// O(1) card lookup. Owned by `ArchiveVaultObservation`; no settings reads.
    func projectVaultPresentation(for song: Song) -> ProjectVaultCardPresentation? {
        vaultObservation.presentation(for: song)
    }

    /// Loads the narrow settings context at an explicit settings boundary, then
    /// rebuilds the card map. The render path itself never calls `SettingsStore`.
    /// Derivation lives in `ArchiveVaultObservation`; this is the explicit
    /// boundary that loads settings once and forwards the snapshot.
    func refreshProjectVaultPresentationContext(notifyWhenChanged: Bool = true) {
        let settings = try? settingsStore.loadSettings()
        vaultObservation.refreshContext(settings: settings, songs: songs, notifyWhenChanged: notifyWhenChanged)
    }

    /// Rebuilds immutable card data at a catalog or snapshot boundary. This is
    /// intentionally internal: `songs` is owned in the primary view-model file
    /// and calls this before it publishes a replacement catalog. Delegates to
    /// the observation owner, which never reads settings here.
    @discardableResult
    func rebuildProjectVaultPresentationCache(
        for songs: [Song]? = nil,
        notifyWhenChanged: Bool = true
    ) -> Bool {
        vaultObservation.rebuildCards(for: songs ?? self.songs, notifyWhenChanged: notifyWhenChanged)
    }
}
