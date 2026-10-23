import Foundation
import NikoMusicCore

/// The songs the archive browser holds: the scan baseline and the visible list,
/// with an id index of the visible list. A value with no I/O and no Vault
/// knowledge; `ArchiveBrowserViewModel.applyCatalogEdit(_:)` is its only writer.
///
/// Every edit reports what it changed (`SongCatalogChange`), so the view model
/// runs the follow-up work of a change in one place. Equal lists stay as held:
/// an unchanged 10,000-song rescan keeps one copy of the catalog and reports
/// an empty change.
struct SongCatalog: Sendable {
    /// What the scan or the cached index found, without archived Vault paths.
    /// The index persist writes this list.
    private(set) var scanned: [Song] = []
    /// The baseline plus archive-only Vault projections when they are shown.
    private(set) var visible: [Song] = []
    /// O(1) lookup into `visible`, rebuilt only when `visible` changes.
    private var visibleByID: [String: Song] = [:]

    func song(id: String) -> Song? {
        visibleByID[id]
    }

    /// The incoming songs that are new or differ from the visible song with the same id.
    func changedSongs(in incoming: [Song]) -> [Song] {
        incoming.songsDiffering(from: visibleByID)
    }

    /// Unique by id, with every unchanged song sharing the held baseline value,
    /// so a rescan that finds nothing new does not keep a second copy.
    func sharingHeldValues(_ incoming: [Song]) -> [Song] {
        SongCatalogDeduplicator.sharingUnchangedValues(SongCatalogDeduplicator.uniqueByID(incoming), from: scanned)
    }

    /// The baseline with `song` added: in place of a song with the same id, or
    /// appended, with the baseline then sorted by display title (New Song).
    func scannedAdding(_ song: Song) -> [Song] {
        var baseline = scanned
        if let index = baseline.firstIndex(where: { $0.id == song.id }) {
            baseline[index] = song
        } else {
            baseline.append(song)
            baseline.sort {
                $0.effectiveDisplayTitle.localizedCaseInsensitiveCompare($1.effectiveDisplayTitle) == .orderedAscending
            }
        }
        return baseline
    }

    /// Replaces both lists. A list equal to the held one stays as held.
    mutating func replaceAll(scanned newScanned: [Song], visible newVisible: [Song]) -> SongCatalogChange {
        var change = SongCatalogChange()
        if !newScanned.equalsConcurrently(scanned) {
            change.scannedChanged = true
            scanned = newScanned
        }
        if !newVisible.equalsConcurrently(visible) {
            change.visibleChanged = true
            // Only songs held before can have changed; new songs are not listed, so
            // a first load of 10,000 songs builds no list at all.
            if !visibleByID.isEmpty {
                change.changed = newVisible.songsDiffering(from: visibleByID).compactMap { song in
                    visibleByID[song.id].map { SongCatalogChange.ChangedSong(before: $0, after: song) }
                }
            }
            let nextByID = Dictionary(newVisible.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            change.removed = visible.filter { nextByID[$0.id] == nil }
            visible = newVisible
            visibleByID = nextByID
        }
        return change
    }

    /// Replaces songs by id in both lists. A song the visible list does not hold
    /// stays out of it. A song the baseline lacks is appended to it, unless
    /// `isArchiveOnly` says it is a Vault projection, which never joins the baseline.
    mutating func replace(_ songs: [Song], isArchiveOnly: (Song) -> Bool) -> SongCatalogChange {
        var change = SongCatalogChange()
        for song in songs {
            if let held = visibleByID[song.id], held != song,
               let index = visible.firstIndex(where: { $0.id == song.id }) {
                change.visibleChanged = true
                change.changed.append(SongCatalogChange.ChangedSong(before: held, after: song))
                visible[index] = song
                visibleByID[song.id] = song
            }
            if let index = scanned.firstIndex(where: { $0.id == song.id }) {
                if scanned[index] != song {
                    change.scannedChanged = true
                    scanned[index] = song
                }
            } else if !isArchiveOnly(song) {
                change.scannedChanged = true
                scanned.append(song)
            }
        }
        return change
    }

    mutating func removeAll() -> SongCatalogChange {
        var change = SongCatalogChange()
        change.scannedChanged = !scanned.isEmpty
        change.visibleChanged = !visible.isEmpty
        change.removed = visible
        scanned = []
        visible = []
        visibleByID = [:]
        return change
    }
}

/// What one catalog edit changed.
struct SongCatalogChange: Equatable, Sendable {
    struct ChangedSong: Equatable, Sendable {
        /// The visible song before the edit.
        let before: Song
        let after: Song
    }

    var scannedChanged = false
    var visibleChanged = false
    /// Visible songs the catalog held before the edit and that now differ, in
    /// visible-list order. Songs new to the catalog are not listed.
    var changed: [ChangedSong] = []
    /// Songs the visible list held before the edit and no longer holds, with
    /// their old values (per-song caches are keyed by id and by project path).
    var removed: [Song] = []

    var isEmpty: Bool { !scannedChanged && !visibleChanged }
}
