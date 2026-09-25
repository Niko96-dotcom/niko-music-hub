import Foundation

public struct JSONOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    private let storageURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private let recovery = RecoveryBox()

    /// Refresh bounds retained missing rows to this many (newest by
    /// `createdAt`), counting only rows whose folder still exists; rows on an
    /// unreachable volume or folder are never pruned, and pruned rows move to
    /// `trimmedArchiveURL`. Every non-missing record is kept regardless of age,
    /// so available outputs are never pruned. Well above the historical
    /// 300-row volume test.
    public static let maxRetainedMissingCount = 1000

    /// One-shot corruption notice: non-nil when the store has quarantined
    /// unreadable JSON since the last take. `OutputInboxRefreshModel` drains
    /// this after a successful pass to surface a one-time warning.
    public func takeCorruptionWarning() -> String? {
        recovery.lock.withLock {
            let warning = recovery.pendingWarning
            recovery.pendingWarning = nil
            return warning
        }
    }

    /// Rows trimmed past `maxRetainedMissingCount` are appended here, beside the store, rather
    /// than deleted.
    public var trimmedArchiveURL: URL {
        let stem = storageURL.deletingPathExtension().lastPathComponent
        let ext = storageURL.pathExtension.isEmpty ? "json" : storageURL.pathExtension
        return storageURL.deletingLastPathComponent().appendingPathComponent("\(stem).trimmed.\(ext)")
    }

    /// Location of the most recent quarantine file, if any.
    public var lastQuarantineURL: URL? {
        recovery.lock.withLock { recovery.lastQuarantineURL }
    }

    public init(
        storageURL: URL,
        fileManager: FileManager = .default
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
    }

    public func listItems() throws -> [OutputInboxItem] {
        try lock.withLock {
            // Read-only: on decode failure this quarantines the bad bytes and
            // reports an empty inbox; the pending warning is drained by the
            // refresh model. Real I/O failures still throw.
            let (items, _) = try loadItemsOrRecover()
            return sortedNewestFirst(items)
        }
    }

    /// Single-pass equivalent of `refreshAvailability()` + `listItems()`.
    ///
    /// Blocking I/O: one JSON load, one availability scan, at most one save,
    /// one sort — all under a single lock hold so an `addItem`/`updateItem`
    /// racing this call is serialized before or after it, never overwritten.
    /// Must be called off the main actor (see `OutputInboxRefreshModel`).
    public func loadRefreshedItems() throws -> [OutputInboxItem] {
        let (snapshot, changed) = try lock.withLock {
            let (items, recovered) = try loadItemsOrRecover()
            let refreshed = applyingAvailability(to: items)
            let changed = recovered || refreshed != items
            if changed {
                try save(refreshed)
            }
            return (sortedNewestFirst(refreshed), changed)
        }
        if changed {
            notifyChanged()
        }
        return snapshot
    }

    public func addItem(_ item: OutputInboxItem) throws {
        try lock.withLock {
            // Same-call recovery: a corrupt file is quarantined above, then
            // the new item is recorded on the resulting empty inbox.
            let (loaded, _) = try loadItemsOrRecover()
            var items = loaded
            if let index = items.firstIndex(where: { existing in
                existing.fileURL.standardizedFileURL == item.fileURL.standardizedFileURL
                    && existing.sourceToolID == item.sourceToolID
            }) {
                let existing = items[index]
                items[index] = OutputInboxItem(
                    id: existing.id,
                    fileURL: item.fileURL.standardizedFileURL,
                    sourceToolID: item.sourceToolID,
                    createdAt: existing.createdAt,
                    status: item.status,
                    metadata: item.metadata
                )
            } else {
                var item = item
                item.fileURL = item.fileURL.standardizedFileURL
                items.append(item)
            }
            try save(items)
        }
        notifyChanged()
    }

    public func updateItem(_ item: OutputInboxItem) throws {
        try lock.withLock {
            let (loaded, _) = try loadItemsOrRecover()
            var items = loaded
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = item
            } else {
                items.append(item)
            }
            try save(items)
        }
        notifyChanged()
    }

    /// Locked load-check-patch-save for an async BPM estimate.
    ///
    /// Under the store lock the current row for `id` is reloaded; the write
    /// is skipped (returning `false`, no save, no notify, no resurrection)
    /// when the row is missing (trimmed/removed while estimating), its status
    /// is not `.available`, its file URL differs from `expectedFileURL`, or
    /// the file itself is currently gone (`regularFileExists`, the same
    /// existence check the availability pass uses). Otherwise only the
    /// supplied `bpmMetadata` entries are merged — every other field,
    /// including newer status-adjacent metadata written concurrently, is
    /// preserved — then the inbox is saved and a change is notified.
    public func patchBPMMetadata(id: UUID, expectedFileURL: URL, bpmMetadata: [String: String]) throws -> Bool {
        let (applied, recovered) = try lock.withLock {
            let (loaded, recovered) = try loadItemsOrRecover()
            var items = loaded
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                return (false, recovered)
            }
            let current = items[index]
            guard current.status == .available else {
                return (false, recovered)
            }
            guard current.fileURL.standardizedFileURL == expectedFileURL.standardizedFileURL else {
                return (false, recovered)
            }
            guard regularFileExists(at: current.fileURL) else {
                return (false, recovered)
            }
            var patched = current
            for (key, value) in bpmMetadata {
                patched.metadata[key] = value
            }
            items[index] = patched
            try save(items)
            return (true, recovered)
        }
        // A quarantined corrupt payload mutates disk even when the patch
        // itself is skipped (no save, no resurrection). Notify outside the
        // lock so the refresh model reloads and drains the pending warning.
        // Normal stale skips without recovery stay quiet. Return value is
        // still whether the keys were merged and saved.
        if applied || recovered {
            notifyChanged()
        }
        return applied
    }

    public func refreshAvailability() throws {
        let changed = try lock.withLock {
            let (items, recovered) = try loadItemsOrRecover()
            let refreshed = applyingAvailability(to: items)
            guard recovered || refreshed != items else { return false }
            try save(refreshed)
            return true
        }
        if changed {
            notifyChanged()
        }
    }

    private func sortedNewestFirst(_ items: [OutputInboxItem]) -> [OutputInboxItem] {
        items.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    /// Availability transitions only; identity (`id`, `createdAt`), input
    /// ordering and dedup are untouched. Refresh additionally bounds the
    /// retained missing rows to `maxRetainedMissingCount` (newest by
    /// `createdAt`); every non-missing record survives regardless of age.
    ///
    /// Only a row whose folder is there but whose file is gone counts toward
    /// the bound. A row whose folder cannot be reached at all (its volume is
    /// unmounted, or the output folder itself is gone) is unavailable rather
    /// than gone: an unplugged drive turns every row on it missing at once,
    /// and the files come back with the drive, so those rows are never
    /// trimmed. Trimmed rows are appended to `trimmedArchiveURL` first; if that
    /// write fails nothing is trimmed.
    private func applyingAvailability(to items: [OutputInboxItem]) -> [OutputInboxItem] {
        let transitioned = items.map { item in
            var copy = item
            if !regularFileExists(at: item.fileURL) {
                copy.status = .missing
            } else if item.status == .pending || item.status == .missing {
                copy.status = .available
            }
            return copy
        }
        var reachableFolders: [String: Bool] = [:]
        let trimmable = transitioned.filter { item in
            guard item.status == .missing else { return false }
            let folder = item.fileURL.deletingLastPathComponent().standardizedFileURL.path
            if let reachable = reachableFolders[folder] { return reachable }
            let reachable = folderIsReachable(atPath: folder)
            reachableFolders[folder] = reachable
            return reachable
        }
        guard trimmable.count > Self.maxRetainedMissingCount else {
            return transitioned
        }
        let trimIDs = Set(
            trimmable
                .sorted { $0.createdAt > $1.createdAt }
                .dropFirst(Self.maxRetainedMissingCount)
                .map(\.id)
        )
        do {
            try archiveTrimmed(transitioned.filter { trimIDs.contains($0.id) })
        } catch {
            return transitioned
        }
        return transitioned.filter { !trimIDs.contains($0.id) }
    }

    /// Appends `rows` to the trimmed-row archive beside the store. An archive
    /// that cannot be decoded is quarantined like the inbox, never overwritten.
    private func archiveTrimmed(_ rows: [OutputInboxItem]) throws {
        let archiveURL = trimmedArchiveURL
        var archived: [OutputInboxItem] = []
        if fileManager.fileExists(atPath: archiveURL.path) {
            let data = try Data(contentsOf: archiveURL)
            do {
                archived = try JSONDecoder().decode([OutputInboxItem].self, from: data)
            } catch {
                guard error is DecodingError else { throw error }
                try fileManager.moveItem(at: archiveURL, to: uniqueQuarantineURL(for: archiveURL))
            }
        }
        let known = Set(archived.map(\.id))
        archived.append(contentsOf: rows.filter { !known.contains($0.id) })
        try fileManager.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archived).write(to: archiveURL, options: .atomic)
    }

    /// The folder exists as a directory and, below `/Volumes/<name>`, that
    /// volume is actually mounted: an unplugged drive can leave an empty
    /// `/Volumes/<name>` directory behind on the startup disk.
    private func folderIsReachable(atPath folder: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        let components = (folder as NSString).pathComponents
        guard components.count >= 3, components[0] == "/", components[1] == "Volumes" else { return true }
        var volumes = stat()
        var volume = stat()
        guard stat("/Volumes", &volumes) == 0,
              stat("/Volumes/" + components[2], &volume) == 0 else { return false }
        return volume.st_dev != volumes.st_dev
    }

    /// Loads the inbox, quarantining it on JSON decode failure (I1). Only
    /// `DecodingError` recovers here: real I/O failures (unreadable file,
    /// missing permissions) still throw and nothing is moved or deleted.
    private func loadItemsOrRecover() throws -> (items: [OutputInboxItem], recovered: Bool) {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return ([], false)
        }

        let data = try Data(contentsOf: storageURL)
        do {
            return (try JSONDecoder().decode([OutputInboxItem].self, from: data), false)
        } catch {
            guard error is DecodingError else { throw error }
            let decodeError = error
            let quarantineURL = uniqueQuarantineURL()
            do {
                // Same-directory rename: atomic, preserves the exact bytes.
                try fileManager.moveItem(at: storageURL, to: quarantineURL)
            } catch {
                // The original could not be preserved; report the decode
                // failure rather than risk data loss.
                throw decodeError
            }
            noteRecovery(quarantineURL: quarantineURL)
            return ([], true)
        }
    }

    private func noteRecovery(quarantineURL: URL) {
        recovery.lock.withLock {
            recovery.lastQuarantineURL = quarantineURL
            recovery.pendingWarning =
                "Output inbox data was unreadable, so it was set aside as \(quarantineURL.lastPathComponent). New outputs will be recorded normally."
        }
    }

    private func uniqueQuarantineURL(for file: URL? = nil, now: Date = Date()) -> URL {
        let file = file ?? storageURL
        let directory = file.deletingLastPathComponent()
        let stem = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension.isEmpty ? "json" : file.pathExtension
        let stamp = Self.quarantineTimestamp(now)
        var candidate = directory.appendingPathComponent(
            "\(stem).corrupt-\(stamp)-\(UUID().uuidString.prefix(8).lowercased()).\(ext)"
        )
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent(
                "\(stem).corrupt-\(stamp)-\(UUID().uuidString.prefix(8).lowercased()).\(ext)"
            )
        }
        return candidate
    }

    private static func quarantineTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func save(_ items: [OutputInboxItem]) throws {
        let directory = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: storageURL, options: .atomic)
        sweepStaleAtomicWriteTemporaries()
    }

    /// `Data.write(options: .atomic)` stages the new file as `<name>.sb-<hash>-<random>`
    /// next to the target and renames it into place. A process that dies between the
    /// two steps leaves the stage file behind forever; 27 of them had accumulated in
    /// Application Support. Only stage files for this store's own file are touched, and
    /// only once they are old enough that no in-flight write can still own them.
    public static let staleTemporaryAge: TimeInterval = 60 * 60

    private func sweepStaleAtomicWriteTemporaries(now: Date = Date()) {
        let directory = storageURL.deletingLastPathComponent()
        let prefix = storageURL.lastPathComponent + ".sb-"
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(prefix) {
            let url = directory.appendingPathComponent(name)
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) > Self.staleTemporaryAge else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func regularFileExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    private func notifyChanged() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .outputInboxDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .outputInboxDidChange, object: nil)
            }
        }
    }
}

/// Lock-guarded quarantine state shared by every copy of the (value-type)
/// `JSONOutputInboxStore`, mirroring how its `NSLock` is shared.
private final class RecoveryBox: @unchecked Sendable {
    let lock = NSLock()
    var pendingWarning: String?
    var lastQuarantineURL: URL?
}
