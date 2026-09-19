import Foundation

public struct JSONOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    private let storageURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        storageURL: URL,
        fileManager: FileManager = .default
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
    }

    public func listItems() throws -> [OutputInboxItem] {
        try lock.withLock {
            sortedNewestFirst(try loadItems())
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
            let items = try loadItems()
            let refreshed = applyingAvailability(to: items)
            let changed = refreshed.map(\.status) != items.map(\.status)
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
            var items = try loadItems()
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
            var items = try loadItems()
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
            let items = try loadItems()
            let refreshed = applyingAvailability(to: items)
            guard refreshed.map(\.status) != items.map(\.status) else { return false }
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

    /// Availability transitions only; identity (`id`, `createdAt`), ordering
    /// input, dedup and record count are untouched. No history cap is applied.
    private func applyingAvailability(to items: [OutputInboxItem]) -> [OutputInboxItem] {
        items.map { item in
            var copy = item
            if !regularFileExists(at: item.fileURL) {
                copy.status = .missing
            } else if item.status == .pending || item.status == .missing {
                copy.status = .available
            }
            return copy
        }
    }

    private func loadItems() throws -> [OutputInboxItem] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return []
        }

        let data = try Data(contentsOf: storageURL)
        return try JSONDecoder().decode([OutputInboxItem].self, from: data)
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
