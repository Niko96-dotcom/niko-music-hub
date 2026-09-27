import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    /// Rebuilds the visible catalog from the scan baseline and the owned
    /// observation snapshots. Composition stays here (`scannedSongs`/`songs`
    /// are view-model state); the archive-only projection itself is owned by
    /// `ArchiveVaultObservation`; projection can read persisted metadata and
    /// inspect archive paths, but never starts a scan or reloads settings.
    func rebuildProjectVaultCatalog() {
        let projected = projectVaultCatalog(from: scannedSongs)
        guard projected.scannedSongs != scannedSongs || projected.visibleSongs != songs else { return }
        mutateCatalog {
            scannedSongs = projected.scannedSongs
            songs = projected.visibleSongs
        }
    }

    /// Compatibility for `ArchiveScanHost` and other non-migrated callers:
    /// projects from the baseline using the current toggle, collaborators,
    /// and the catalog metadata store. The metadata-load failure warning is
    /// preserved via `recordPersistenceWarning`. New code should call
    /// `vaultObservation.projectCatalog(from:showArchived:collaborators:metadataStore:onMetadataWarning:)`.
    func projectVaultCatalog(from baselineSongs: [Song]) -> (scannedSongs: [Song], visibleSongs: [Song]) {
        vaultObservation.projectCatalog(
            from: baselineSongs,
            showArchived: showArchivedProjects,
            collaborators: collaborators,
            metadataStore: catalog.songMetadataStore,
            onMetadataWarning: { [weak self] message in self?.recordPersistenceWarning(message) }
        )
    }
}
