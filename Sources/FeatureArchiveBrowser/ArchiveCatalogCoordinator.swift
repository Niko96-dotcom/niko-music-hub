import AppCore
import Foundation
import NikoMusicCore

/// Fail-closed song-metadata integrity state (M1). Tracks per-row corruption
/// from the last tolerant load plus whole-load failure, so explicit edits can
/// be refused without a fresh full-table read. Reference type so the
/// value-type coordinator can update it from non-mutating methods.
final class SongMetadataIntegrityState: @unchecked Sendable {
    private let lock = NSLock()
    private var corruptIDs: Set<String> = []
    /// Songs added without a successful metadata read (new-song merge failed):
    /// their stored details are unknown, so only they wait for the next load.
    private var unverifiedIDs: Set<String> = []
    private var loadFailed = false
    /// User-facing names (display title, else folder name) for warning copy.
    private var names: [String: String] = [:]

    func recordLoadSuccess(corruptSongIDs: [String], names newNames: [String: String] = [:]) {
        lock.withLock {
            corruptIDs = Set(corruptSongIDs)
            unverifiedIDs.removeAll()
            loadFailed = false
            names.merge(newNames) { _, latest in latest }
        }
    }

    func recordLoadFailure() {
        lock.withLock { loadFailed = true }
    }

    func recordCorrupt(songIDs: [String], names newNames: [String: String] = [:]) {
        lock.withLock {
            corruptIDs.formUnion(songIDs)
            names.merge(newNames) { _, latest in latest }
        }
    }

    func clearCorrupt(songIDs: some Sequence<String>) {
        lock.withLock { corruptIDs.subtract(songIDs) }
    }

    func recordUnverified(songID: String, name: String) {
        lock.withLock {
            unverifiedIDs.insert(songID)
            names[songID] = name
        }
    }

    func corruptSnapshot() -> Set<String> {
        lock.withLock { corruptIDs }
    }

    func isUnverified(_ songID: String) -> Bool {
        lock.withLock { unverifiedIDs.contains(songID) }
    }

    func didFailLoad() -> Bool {
        lock.withLock { loadFailed }
    }

    /// Display title if known, otherwise the song folder's name. Never the raw ID.
    func name(for songID: String) -> String {
        lock.withLock { names[songID] } ?? SongMetadataIntegrityCopy.folderName(for: songID)
    }
}

/// Plain-language copy for song-detail integrity. Songs are named by display
/// title (or folder name); raw song IDs (paths) never reach the user.
enum SongMetadataIntegrityCopy {
    static let loadFailedEditsBlocked =
        "Song details could not be read; edits are blocked until song details reload — nothing was overwritten."
    static let loadFailedScan = "Song details could not be read; nothing was overwritten."

    static func name(of song: Song) -> String {
        let title = song.effectiveDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? song.originalFolderName : title
    }

    static func folderName(for songID: String) -> String {
        URL(fileURLWithPath: songID).lastPathComponent
    }

    static func corrupt(_ names: [String]) -> String {
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if sorted.count == 1 {
            return "Details for “\(sorted[0])” couldn't be read, so edits to it are paused; nothing was overwritten."
        }
        let shown = sorted.prefix(3).map { "“\($0)”" }.joined(separator: ", ")
        let remainder = sorted.count > 3 ? ", …" : ""
        return "Details for \(sorted.count) songs couldn't be read (\(shown)\(remainder)), so edits to them are paused; nothing was overwritten."
    }

    static func unverified(_ name: String) -> String {
        "Details for “\(name)” couldn't be read yet, so edits to it are paused until the archive refreshes; nothing was overwritten."
    }

    static func repaired(names: [String], cleared: [SongUserMetadataListColumn]) -> String {
        let head = names.count == 1 ? "Repaired “\(names[0])”." : "Repaired \(names.count) songs."
        let order = SongUserMetadataListColumn.allCases
        let labels = order.filter(cleared.contains).map(\.label)
        guard !labels.isEmpty else { return head }
        return "\(head) Cleared: \(labels.joined(separator: ", "))."
    }

    static func repairFailed(names: [String]) -> String {
        names.count == 1
            ? "Couldn't repair “\(names[0])”; nothing was changed."
            : "Couldn't repair \(names.count) songs; nothing was changed."
    }

    /// True for any song-detail integrity warning this module writes.
    static func isIntegrityWarning(_ message: String) -> Bool {
        message.hasPrefix("Details for ") || message.hasPrefix("Song details could not be read")
    }
}

/// Outcome of an explicit song-detail repair (D2).
struct SongMetadataRepairResult {
    /// Freshly reloaded metadata for every repaired song that now decodes.
    var reloaded: [String: SongUserMetadata] = [:]
    /// Lists that were reset across all repaired songs.
    var clearedLists: [SongUserMetadataListColumn] = []
    /// Songs that could not be repaired (store refused or still unreadable).
    var failedSongIDs: [String] = []
}

/// Minimal internal seam for the incremental-cancel regression: awaited at the
/// start of the actual filesystem operation (after the orchestrator pre-scan
/// hold) so a test can park the batch while its I/O is in flight. Production
/// leaves `hold` nil. Reference type so the value-type coordinator can expose
/// it through a `let` catalog.
final class ArchiveIncrementalTestProbe {
    var hold: (() async -> Void)?
}

/// Scan, cache, and metadata merge/persist for the archive catalog. Owned by ``ArchiveBrowserViewModel``;
/// browse/UI orchestration stays in the view model.
@MainActor
struct ArchiveCatalogCoordinator {
    let archiveIndexStore: (any ArchiveIndexStoring)?
    let songMetadataStore: (any SongUserMetadataStoring)?
    let collaboratorStore: (any CollaboratorStoring)?
    let diagnostics: Diagnostics
    private let settingsStore: SettingsStore?
    private let integrity: SongMetadataIntegrityState
    /// Narrow internal test seam (see `ArchiveIncrementalTestProbe`).
    let incrementalTestProbe = ArchiveIncrementalTestProbe()

    init(
        archiveIndexStore: (any ArchiveIndexStoring)?,
        songMetadataStore: (any SongUserMetadataStoring)?,
        collaboratorStore: (any CollaboratorStoring)?,
        diagnostics: Diagnostics,
        settingsStore: SettingsStore? = nil,
        integrity: SongMetadataIntegrityState = SongMetadataIntegrityState()
    ) {
        self.archiveIndexStore = archiveIndexStore
        self.songMetadataStore = songMetadataStore
        self.collaboratorStore = collaboratorStore
        self.diagnostics = diagnostics
        self.settingsStore = settingsStore
        self.integrity = integrity
    }

    private static func loadExclusionTerms(settingsStore: SettingsStore?) -> [String] {
        guard let settingsStore,
              let settings = try? settingsStore.loadSettings() else { return [] }
        return ScanExclusionPolicy.terms(from: settings.scanExclusionTerms)
    }

    func performScanSynchronously(roots: [URL]) throws -> ScanResult {
        let scanner = MusicArchiveScanner(
            exclusionTerms: Self.loadExclusionTerms(settingsStore: settingsStore)
        )
        return try scanner.scan(roots: roots)
    }

    func performScanDetached(roots: [URL]) async throws -> ScanResult {
        try Task.checkCancellation()
        let exclusionTerms = Self.loadExclusionTerms(settingsStore: settingsStore)
        let scanTask = Task.detached(priority: .userInitiated) {
            try MusicArchiveScanner(exclusionTerms: exclusionTerms).scan(roots: roots)
        }
        return try await withTaskCancellationHandler(operation: {
            let result = try await scanTask.value
            try Task.checkCancellation()
            return result
        }, onCancel: {
            scanTask.cancel()
        })
    }

    struct IncrementalFilesystemApplyResult: Sendable {
        let songs: [Song]
        let diagnostics: ArchiveScanDiagnostics
        let incrementalSongCount: Int
        let firstUpdatedTitle: String?
        let scannedAt: Date
        /// Metadata-load degradation observed while merging (never a persist request).
        let persistenceWarning: String?

        var statusMessage: String {
            if incrementalSongCount == 1, let firstUpdatedTitle {
                return "Updated \(firstUpdatedTitle) from filesystem change (\(songs.count) songs)."
            }
            return "Updated \(incrementalSongCount) songs from filesystem change (\(songs.count) total)."
        }

        var catalogApplyResult: CatalogScanApplyResult {
            CatalogScanApplyResult(
                songs: songs,
                diagnostics: diagnostics,
                statusMessage: statusMessage,
                scannedAt: scannedAt,
                shouldPersistUserMetadata: false,
                persistenceWarning: persistenceWarning,
                announceCompletion: false
            )
        }
    }

    struct CatalogScanApplyResult: Sendable {
        let songs: [Song]
        let diagnostics: ArchiveScanDiagnostics
        let statusMessage: String
        let scannedAt: Date
        /// Retained for source compatibility. Always false: scans never write
        /// song metadata (P0 data-loss fix — a whole-catalog scan-time upsert
        /// overwrote stored titles/notes/status whenever the metadata load
        /// failed, and blocked the main actor on a full-table write). User
        /// edits persist single rows via `persistUserMetadata`.
        let shouldPersistUserMetadata: Bool
        /// Non-nil when the metadata load behind this scan was degraded
        /// (unreadable store or corrupt rows). Nothing was overwritten.
        let persistenceWarning: String?
        /// Full scans announce completion; incremental applies stay quiet (NMH-042).
        let announceCompletion: Bool

        init(
            songs: [Song],
            diagnostics: ArchiveScanDiagnostics,
            statusMessage: String,
            scannedAt: Date,
            shouldPersistUserMetadata: Bool = false,
            persistenceWarning: String? = nil,
            announceCompletion: Bool = false
        ) {
            self.songs = songs
            self.diagnostics = diagnostics
            self.statusMessage = statusMessage
            self.scannedAt = scannedAt
            self.shouldPersistUserMetadata = shouldPersistUserMetadata
            self.persistenceWarning = persistenceWarning
            self.announceCompletion = announceCompletion
        }
    }

    func applyFullScanResult(
        result: ScanResult,
        roots: [URL],
        collaborators: [Collaborator],
        scannedAt: Date
    ) -> CatalogScanApplyResult {
        let uniqueSongs = SongCatalogDeduplicator.uniqueByID(result.songs)
        let merged = mergeUserMetadataWithReport(into: uniqueSongs, collaborators: collaborators)
        let mergedResult = ScanResult(
            songs: merged.songs,
            globalWarnings: result.globalWarnings,
            skippedEntries: result.skippedEntries
        )
        let built = buildDiagnostics(result: mergedResult, roots: roots, scannedAt: scannedAt)
        return CatalogScanApplyResult(
            songs: merged.songs,
            diagnostics: built,
            statusMessage: built.compactSummaryLine,
            scannedAt: scannedAt,
            shouldPersistUserMetadata: false,
            persistenceWarning: merged.persistenceWarning,
            announceCompletion: true
        )
    }

    func applyIncrementalFilesystemUpdate(
        changedPaths: [URL],
        roots: [URL],
        existingSongs: [Song],
        collaborators: [Collaborator],
        priorDiagnostics: ArchiveScanDiagnostics?
    ) async throws -> IncrementalFilesystemApplyResult? {
        let scannedAt = Date()
        if let hold = incrementalTestProbe.hold {
            await hold()
        }
        let incremental = try await performIncrementalScanDetached(
            changedPaths: changedPaths,
            roots: roots,
            existingSongs: existingSongs
        )
        guard !incremental.affectedSongIDs.isEmpty || !incremental.result.songs.isEmpty else {
            return nil
        }

        // A batch that touches song folders or root entries can stat every existing song
        // folder — keep the merge off the main actor (slow/external volumes make each stat visible).
        let unaffectedSongFoldersMayHaveMoved = ArchiveSongFolderResolver.mayMoveSongFolders(
            changedPaths: changedPaths,
            roots: roots
        )
        let merged = await Task.detached(priority: .userInitiated) { [result = incremental.result, affectedSongIDs = incremental.affectedSongIDs] in
            Self.mergeIncrementalScan(
                existing: existingSongs,
                incremental: result,
                affectedSongIDs: affectedSongIDs,
                unaffectedSongFoldersMayHaveMoved: unaffectedSongFoldersMayHaveMoved
            )
        }.value
        let uniqueMerged = SongCatalogDeduplicator.uniqueByID(merged)
        let withMetadata = mergeUserMetadataWithReport(into: uniqueMerged, collaborators: collaborators)
        let mergedResult = ScanResult(
            songs: withMetadata.songs,
            globalWarnings: incremental.result.globalWarnings,
            skippedEntries: incremental.result.skippedEntries
        )
        let built = buildDiagnostics(result: mergedResult, roots: roots, scannedAt: scannedAt)
        return IncrementalFilesystemApplyResult(
            songs: withMetadata.songs,
            diagnostics: ArchiveScanDiagnosticsBuilder.mergeIncremental(prior: priorDiagnostics, built: built),
            incrementalSongCount: incremental.result.songs.count,
            firstUpdatedTitle: incremental.result.songs.first?.displayTitle,
            scannedAt: scannedAt,
            persistenceWarning: withMetadata.persistenceWarning
        )
    }

    func performIncrementalScanDetached(
        changedPaths: [URL],
        roots: [URL],
        existingSongs: [Song]
    ) async throws -> (result: ScanResult, affectedSongIDs: Set<String>) {
        try Task.checkCancellation()
        let resolution = ArchiveSongFolderResolver.resolve(changedPaths: changedPaths, roots: roots)
        guard !resolution.isEmpty else {
            return (ScanResult(), [])
        }
        let exclusionTerms = Self.loadExclusionTerms(settingsStore: settingsStore)
        let scanTask = Task.detached(priority: .userInitiated) {
            try MusicArchiveScanner(exclusionTerms: exclusionTerms)
                .scanIncremental(resolution: resolution, roots: roots)
        }
        let result = try await withTaskCancellationHandler(operation: {
            let result = try await scanTask.value
            try Task.checkCancellation()
            return result
        }, onCancel: {
            scanTask.cancel()
        })
        let affectedSongIDs = Self.affectedSongIDs(
            resolution: resolution,
            existing: existingSongs
        )
        return (result, affectedSongIDs)
    }

    nonisolated static func mergeIncrementalScan(
        existing: [Song],
        incremental: ScanResult,
        affectedSongIDs: Set<String>,
        fileManager: FileManager = .default,
        unaffectedSongFoldersMayHaveMoved: Bool = true
    ) -> [Song] {
        let uniqueExisting = SongCatalogDeduplicator.uniqueByID(existing)
        let uniqueIncoming = SongCatalogDeduplicator.uniqueByID(incremental.songs)
        let incomingByID = uniqueIncoming.reduce(into: [String: Song]()) { $0[$1.id] = $1 }
        var merged: [Song] = []
        merged.reserveCapacity(uniqueExisting.count + uniqueIncoming.count)

        for song in uniqueExisting {
            // Drop ghosts even when FSEvents did not mark the old path as affected
            // (common for Finder renames that only emit create events on the new name).
            // Only a batch touching root entries can do that; a batch confined to song
            // folders (a Cubase save) leaves every other song as it was, unstat'ed.
            if !affectedSongIDs.contains(song.id) {
                if !unaffectedSongFoldersMayHaveMoved || fileManager.fileExists(atPath: song.folderPath.path) {
                    merged.append(song)
                }
                continue
            }
            if let updated = incomingByID[song.id] {
                merged.append(updated)
            } else if fileManager.fileExists(atPath: song.folderPath.path),
                      (try? fileManager.attributesOfItem(atPath: song.folderPath.path)[.type]) as? FileAttributeType
                        != .typeSymbolicLink {
                // A folder now replaced by a symlink is skipped by scans, as a full scan does.
                merged.append(song)
            }
        }

        let mergedIDs = Set(merged.map(\.id))
        for song in uniqueIncoming where !mergedIDs.contains(song.id) {
            merged.append(song)
        }

        merged.sort { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        return merged
    }

    private static func affectedSongIDs(
        resolution: ArchiveSongFolderResolver.Resolution,
        existing: [Song]
    ) -> Set<String> {
        // Song.id is the standardized song-folder path; resolver returns folder URLs.
        var ids = Set(resolution.songFolders.map { $0.standardizedFileURL.path })

        guard !resolution.rootsForRootLevelScan.isEmpty else { return ids }

        let rootPaths = Set(resolution.rootsForRootLevelScan.map { $0.standardizedFileURL.path })
        for song in existing {
            let songPath = song.folderPath.standardizedFileURL.path
            for rootPath in rootPaths where isRootLevelCPRPath(songPath, ofRoot: rootPath) {
                ids.insert(song.id)
            }
        }
        return ids
    }

    private static func isRootLevelCPRPath(_ path: String, ofRoot rootPath: String) -> Bool {
        guard path.hasPrefix(rootPath + "/") else { return false }
        let relative = String(path.dropFirst(rootPath.count + 1))
        return !relative.contains("/") && ProjectFileFormat(url: URL(fileURLWithPath: path)) != nil
    }

    func buildDiagnostics(
        result: ScanResult,
        roots: [URL],
        scannedAt: Date
    ) -> ArchiveScanDiagnostics {
        ArchiveScanDiagnosticsBuilder.build(
            result: result,
            roots: roots,
            scannedAt: scannedAt
        )
    }

    /// Merge with integrity reporting. A throwing store yields an empty merge
    /// plus "Song details could not be read; nothing was overwritten." A store
    /// reporting corrupt rows merges the good rows and names the corrupt ones.
    /// Either way nothing is written back: scans never persist metadata, so a
    /// degraded load can never clobber stored titles/notes/status.
    /// Fail-closed edit gate (M1). Non-nil when an explicit edit for `songID`
    /// must be refused without touching SQLite: either the last metadata load
    /// failed (all in-memory values are incomplete) or this row is known
    /// corrupt (in-memory values are defaulted). No full-table read here; uses
    /// only the last load's integrity snapshot plus the store's single-row
    /// backstop. Cleared only by a later successful load with correct data.
    func metadataEditBlockWarning(for songID: String) -> String? {
        if integrity.didFailLoad() {
            return SongMetadataIntegrityCopy.loadFailedEditsBlocked
        }
        if integrity.corruptSnapshot().contains(songID) {
            return SongMetadataIntegrityCopy.corrupt([integrity.name(for: songID)])
        }
        if integrity.isUnverified(songID) {
            return SongMetadataIntegrityCopy.unverified(integrity.name(for: songID))
        }
        return nil
    }

    /// Song IDs whose stored rows are known corrupt (repairable).
    func corruptSongIDs() -> Set<String> {
        integrity.corruptSnapshot()
    }

    /// Current degraded-load warning for surfaces (like cache bootstrap) that
    /// do not already return a per-scan warning. Nil when integrity is clean.
    func metadataIntegrityWarning() -> String? {
        if integrity.didFailLoad() {
            return SongMetadataIntegrityCopy.loadFailedEditsBlocked
        }
        let corrupt = integrity.corruptSnapshot()
        guard !corrupt.isEmpty else { return nil }
        return SongMetadataIntegrityCopy.corrupt(corrupt.map { integrity.name(for: $0) })
    }

    func mergeUserMetadataWithReport(
        into scanned: [Song],
        collaborators: [Collaborator]
    ) -> (songs: [Song], persistenceWarning: String?) {
        guard songMetadataStore != nil || collaboratorStore != nil else { return (scanned, nil) }
        var metadata: [String: SongUserMetadata] = [:]
        var warning: String? = nil
        if let songMetadataStore {
            switch loadMetadataReport(songMetadataStore) {
            case .success(let report):
                metadata = report.metadata
                let names = Self.names(for: scanned, ids: report.corruptSongIDs)
                integrity.recordLoadSuccess(corruptSongIDs: report.corruptSongIDs, names: names)
                if !report.corruptSongIDs.isEmpty {
                    warning = SongMetadataIntegrityCopy.corrupt(report.corruptSongIDs.map { integrity.name(for: $0) })
                    diagnostics.log(.error, "Song metadata skipped corrupt rows for: \(report.corruptSongIDs.sorted().joined(separator: ", "))")
                }
            case .failure(let error):
                diagnostics.log(.error, "Song metadata load failed: \(error)")
                metadata = [:]
                integrity.recordLoadFailure()
                warning = SongMetadataIntegrityCopy.loadFailedScan
            }
        }
        let map = Dictionary(uniqueKeysWithValues: collaborators.map { ($0.id, $0) })
        let songs = ArchiveMetadataMerger.merge(
            scanned: scanned,
            metadataByID: metadata,
            collaboratorsByID: map
        )
        return (songs, warning)
    }

    /// Tolerant full read, shared by every metadata merge.
    private func loadMetadataReport(
        _ store: any SongUserMetadataStoring
    ) -> Result<SongUserMetadataLoadReport, any Error> {
        Result {
            if let reporting = store as? any SongUserMetadataLoadReporting {
                return try reporting.loadAllWithReport()
            }
            return SongUserMetadataLoadReport(metadata: try store.loadAll())
        }
    }

    /// `scannedTitleOnly` ignores in-memory title edits (an edit the store
    /// just refused must not become the song's name in the warning).
    private static func names(for songs: [Song], ids: [String], scannedTitleOnly: Bool = false) -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        let wanted = Set(ids)
        var names: [String: String] = [:]
        for song in songs where wanted.contains(song.id) {
            if scannedTitleOnly {
                let title = song.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                names[song.id] = title.isEmpty ? song.originalFolderName : title
            } else {
                names[song.id] = SongMetadataIntegrityCopy.name(of: song)
            }
        }
        return names
    }

    /// Merge for a single song that is being ADDED to the live catalog (new
    /// song creation). The rest of the catalog is not replaced, so this never
    /// raises or clears the global edit gate (D3): a failed read only pauses
    /// edits to the new song, whose stored details are unknown, and returns a
    /// one-off warning. Corrupt rows found on the way are added to the per-song
    /// gate (that only ever blocks more, never less).
    func mergeUserMetadataForNewSong(
        _ song: Song,
        collaborators: [Collaborator]
    ) -> (song: Song, warning: String?) {
        guard songMetadataStore != nil || collaboratorStore != nil else { return (song, nil) }
        var metadata: SongUserMetadata?
        var warning: String?
        if let songMetadataStore {
            switch loadMetadataReport(songMetadataStore) {
            case .success(let report):
                metadata = report.metadata[song.id]
                if !report.corruptSongIDs.isEmpty {
                    integrity.recordCorrupt(
                        songIDs: report.corruptSongIDs,
                        names: Self.names(for: [song], ids: report.corruptSongIDs)
                    )
                }
                if report.corruptSongIDs.contains(song.id) {
                    warning = SongMetadataIntegrityCopy.corrupt([SongMetadataIntegrityCopy.name(of: song)])
                }
            case .failure(let error):
                diagnostics.log(.error, "Song metadata load for new song failed: \(error)")
                let name = SongMetadataIntegrityCopy.name(of: song)
                integrity.recordUnverified(songID: song.id, name: name)
                warning = SongMetadataIntegrityCopy.unverified(name)
            }
        }
        let map = Dictionary(uniqueKeysWithValues: collaborators.map { ($0.id, $0) })
        let merged = ArchiveMetadataMerger.merge(scanned: song, metadata: metadata, collaboratorsByID: map)
        return (merged, warning)
    }

    /// Explicit repair (D2): salvage each row through the store, then re-read
    /// and unblock only the songs whose rows now decode. Other songs' gates are
    /// untouched (their in-memory values were never replaced), and any newly
    /// corrupt rows seen on the re-read are added to the gate.
    func repairSongMetadata(songIDs: [String]) -> SongMetadataRepairResult {
        var result = SongMetadataRepairResult()
        guard let songMetadataStore, !songIDs.isEmpty else {
            result.failedSongIDs = songIDs
            return result
        }
        guard let repairing = songMetadataStore as? any SongUserMetadataRepairing else {
            result.failedSongIDs = songIDs
            return result
        }
        var cleared = Set<SongUserMetadataListColumn>()
        var attempted: [String] = []
        for songID in songIDs {
            do {
                if let repair = try repairing.repairCorruptRow(songID: songID) {
                    cleared.formUnion(repair.clearedLists)
                    diagnostics.log(.info, "Repaired song metadata row \(songID); cleared \(repair.clearedLists.map(\.rawValue))")
                }
                attempted.append(songID)
            } catch {
                diagnostics.log(.error, "Song metadata repair failed for \(songID): \(error)")
                result.failedSongIDs.append(songID)
            }
        }
        result.clearedLists = SongUserMetadataListColumn.allCases.filter(cleared.contains)
        switch loadMetadataReport(songMetadataStore) {
        case .success(let report):
            let stillCorrupt = Set(report.corruptSongIDs)
            if !stillCorrupt.isEmpty {
                integrity.recordCorrupt(songIDs: report.corruptSongIDs)
            }
            let healed = attempted.filter { !stillCorrupt.contains($0) }
            integrity.clearCorrupt(songIDs: healed)
            for songID in healed {
                result.reloaded[songID] = report.metadata[songID]
                    ?? SongUserMetadata(songID: songID)
            }
            result.failedSongIDs.append(contentsOf: attempted.filter { stillCorrupt.contains($0) })
        case .failure(let error):
            // Repaired rows stay blocked until a later read proves them clean.
            diagnostics.log(.error, "Song metadata reload after repair failed: \(error)")
            result.failedSongIDs.append(contentsOf: attempted)
        }
        return result
    }

    func mergeUserMetadata(
        into scanned: [Song],
        collaborators: [Collaborator]
    ) -> [Song] {
        let merged = mergeUserMetadataWithReport(into: scanned, collaborators: collaborators)
        if let warning = merged.persistenceWarning {
            diagnostics.log(.error, warning)
        }
        return merged.songs
    }

    /// Detached cache load without integrity side effects. The caller applies
    /// the returned integrity only after confirming the result is still current
    /// (same root generation and no fresher scan applied); a stale cache result
    /// must never clear or set the fail-closed gate. Empty/failed results carry
    /// no integrity and must leave valid scan state untouched.
    struct ArchiveCacheLoadReport: Sendable {
        let result: ArchiveCacheLoadResult
        let corruptSongIDs: [String]
        let metadataLoadFailed: Bool
        let hasMetadataSources: Bool
    }

    /// Launch-time cache bootstrap. Decoding a real catalog snapshot is tens of MB of JSON,
    /// so the load, metadata merge, and decode all run off the main actor.
    func loadCachedSongsReportDetached(
        roots: [URL],
        collaborators: [Collaborator]
    ) async -> ArchiveCacheLoadReport {
        guard let archiveIndexStore else {
            return ArchiveCacheLoadReport(
                result: .empty,
                corruptSongIDs: [],
                metadataLoadFailed: false,
                hasMetadataSources: false
            )
        }
        let songMetadataStore = self.songMetadataStore
        let hasMetadataSources = songMetadataStore != nil || collaboratorStore != nil
        let outcome = await Task.detached(priority: .userInitiated) {
            () -> (result: ArchiveCacheLoadResult, logs: [String], corruptSongIDs: [String], metadataLoadFailed: Bool) in
            let snapshot: ArchiveIndexSnapshot?
            do {
                snapshot = try archiveIndexStore.loadLatest()
            } catch {
                return (
                    .failed("Archive cache could not be loaded: \(error.localizedDescription)"),
                    ["Archive cache load failed: \(error)"],
                    [],
                    false
                )
            }
            guard let snapshot, snapshot.matchesCurrentRoots(roots), !snapshot.songs.isEmpty else {
                return (.empty, [], [], false)
            }
            let uniqueSongs = SongCatalogDeduplicator.uniqueByID(snapshot.songs)
            guard hasMetadataSources else {
                return (
                    .loaded(
                        songs: PreviewAutoSelectionNormalizer.normalized(uniqueSongs),
                        scannedAt: snapshot.scannedAt
                    ),
                    [],
                    [],
                    false
                )
            }
            var logs: [String] = []
            let metadata: [String: SongUserMetadata]
            var corruptSongIDs: [String] = []
            var metadataLoadFailed = false
            do {
                if let reporting = songMetadataStore as? any SongUserMetadataLoadReporting {
                    let report = try reporting.loadAllWithReport()
                    metadata = report.metadata
                    corruptSongIDs = report.corruptSongIDs
                    if !report.corruptSongIDs.isEmpty {
                        logs.append("Song metadata skipped corrupt rows for: \(report.corruptSongIDs.sorted().joined(separator: ", "))")
                    }
                } else {
                    metadata = try songMetadataStore?.loadAll() ?? [:]
                }
            } catch {
                logs.append("Song metadata load failed: \(error)")
                metadata = [:]
                metadataLoadFailed = true
            }
            let map = Dictionary(uniqueKeysWithValues: collaborators.map { ($0.id, $0) })
            let merged = ArchiveMetadataMerger.merge(
                scanned: uniqueSongs,
                metadataByID: metadata,
                collaboratorsByID: map
            )
            return (
                .loaded(
                    songs: PreviewAutoSelectionNormalizer.normalized(merged),
                    scannedAt: snapshot.scannedAt
                ),
                logs,
                corruptSongIDs,
                metadataLoadFailed
            )
        }.value
        for log in outcome.logs {
            diagnostics.log(.error, log)
        }
        return ArchiveCacheLoadReport(
            result: outcome.result,
            corruptSongIDs: outcome.corruptSongIDs,
            metadataLoadFailed: outcome.metadataLoadFailed,
            hasMetadataSources: hasMetadataSources
        )
    }

    /// Legacy entry point for direct callers. Applies cache integrity
    /// immediately; the launch bootstrap in the view model uses
    /// `loadCachedSongsReportDetached` plus `applyCacheLoadReport` so a stale
    /// result can be dropped before it touches the gate.
    func loadCachedSongsDetached(
        roots: [URL],
        collaborators: [Collaborator]
    ) async -> ArchiveCacheLoadResult {
        let report = await loadCachedSongsReportDetached(roots: roots, collaborators: collaborators)
        applyCacheLoadReport(report)
        return report.result
    }

    /// Records cache integrity for a current result. No-op for empty/failed
    /// results so missing cache never clears valid scan state.
    /// Fail-closed (M1): current loaded snapshots feed the same gate as scans,
    /// otherwise an edit before the first full scan could clobber a corrupt
    /// row (or defaulted values after a failed load) with no visible block.
    func applyCacheLoadReport(_ report: ArchiveCacheLoadReport) {
        if case .loaded(let songs, _) = report.result {
            if report.metadataLoadFailed {
                integrity.recordLoadFailure()
            } else if report.hasMetadataSources {
                integrity.recordLoadSuccess(
                    corruptSongIDs: report.corruptSongIDs,
                    names: Self.names(for: songs, ids: report.corruptSongIDs)
                )
            }
        }
    }

    /// Single-row (or single-edit) persist for explicit user edits and new songs.
    /// Never called for whole-catalog scans: scans must not rewrite stored
    /// metadata (P0 data-loss fix). Fail-closed (M1): refuses blocked songs
    /// without touching SQLite (no row or status-history mutation); good rows
    /// in the same request still persist. No full-table read here.
    func persistUserMetadata(for songs: [Song]) -> String? {
        guard let songMetadataStore, !songs.isEmpty else { return nil }
        var allowed: [Song] = []
        allowed.reserveCapacity(songs.count)
        var blockWarnings: [String] = []
        for song in songs {
            if let block = metadataEditBlockWarning(for: song.id) {
                blockWarnings.append(block)
            } else {
                allowed.append(song)
            }
        }
        var persistWarning: String?
        if !allowed.isEmpty {
            let items = allowed.map { SongUserMetadata.from(song: $0) }
            do {
                try songMetadataStore.upsertAll(items)
            } catch let corrupt as SongUserMetadataCorruptRowError {
                // Store-level backstop: corruption appeared after the last load
                // (or a caller bypassed the pre-check). Record it so later edits
                // block without another store hit, and warn visibly.
                integrity.recordCorrupt(songIDs: corrupt.songIDs, names: Self.names(for: allowed, ids: corrupt.songIDs, scannedTitleOnly: true))
                let sorted = corrupt.songIDs.sorted()
                diagnostics.log(.error, "Refused metadata overwrite for corrupt rows: \(sorted.joined(separator: ", "))")
                persistWarning = SongMetadataIntegrityCopy.corrupt(sorted.map { integrity.name(for: $0) })
            } catch {
                diagnostics.log(.error, "Song metadata save failed: \(error)")
                persistWarning = "Song metadata could not be saved: \(error.localizedDescription)"
            }
        }
        if blockWarnings.isEmpty { return persistWarning }
        let blockMessage = blockWarnings.joined(separator: " ")
        if let persistWarning { return "\(blockMessage) \(persistWarning)" }
        return blockMessage
    }

    /// Off-main-actor variant of ``persistCachedIndex(roots:songs:scannedAt:)`` — encoding the
    /// whole catalog to JSON is proportional to catalog size and stalls the UI on the main actor.
    func persistCachedIndexDetached(roots: [URL], songs: [Song], scannedAt: Date) async -> String? {
        guard let archiveIndexStore else { return nil }
        let snapshot = ArchiveIndexSnapshot(
            roots: roots.map { $0.standardizedFileURL.path },
            songs: SongCatalogDeduplicator.uniqueByID(songs),
            scannedAt: scannedAt
        )
        let failure = await Task.detached(priority: .utility) { () -> (log: String, warning: String)? in
            do {
                try archiveIndexStore.save(snapshot)
                return nil
            } catch {
                return ("\(error)", error.localizedDescription)
            }
        }.value
        guard let failure else { return nil }
        diagnostics.log(.error, "Archive cache save failed: \(failure.log)")
        return "Archive cache could not be saved: \(failure.warning)"
    }
}

enum ArchiveCacheLoadResult {
    case loaded(songs: [Song], scannedAt: Date)
    case empty
    case failed(String)
}
