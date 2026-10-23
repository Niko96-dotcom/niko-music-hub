import AppCore
import Foundation
import NikoMusicCore

extension ArchiveBrowserViewModel {
    /// Projects a baseline with the current "Show archived" toggle, collaborators
    /// and the catalog metadata store; `applyCatalogEdit(_:)` calls it for every
    /// edit. The archive-only projection itself is owned by
    /// `ArchiveVaultObservation`: it can read persisted metadata and inspect
    /// archive paths, but never starts a scan or reloads settings. A metadata-load
    /// failure is reported through `recordPersistenceWarning`.
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
