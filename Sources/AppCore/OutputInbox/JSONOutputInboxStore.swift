import Foundation

public struct JSONOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    private let storageURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private let recovery = RecoveryBox()

    /// Refresh bounds retained missing rows to this many (newest by
    /// `createdAt`). Every non-missing record is kept regardless of age, so
    /// available outputs are never pruned. Well above the historical 300-row
    /// volume test.
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
        let missingCount = transitioned.reduce(into: 0) { count, item in
            if item.status == .missing { count += 1 }
        }
        guard missingCount > Self.maxRetainedMissingCount else {
            return transitioned
        }
        let keepIDs = Set(
            transitioned
                .filter { $0.status == .missing }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(Self.maxRetainedMissingCount)
                .map(\.id)
        )
        return transitioned.filter { $0.status != .missing || keepIDs.contains($0.id) }
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

    private func uniqueQuarantineURL(now: Date = Date()) -> URL {
        let directory = storageURL.deletingLastPathComponent()
        let stem = storageURL.deletingPathExtension().lastPathComponent
        let ext = storageURL.pathExtension.isEmpty ? "json" : storageURL.pathExtension
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
