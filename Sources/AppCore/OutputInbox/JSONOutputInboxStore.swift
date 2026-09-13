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
            try loadItems()
                .sorted { lhs, rhs in
                    lhs.createdAt > rhs.createdAt
                }
        }
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
            let refreshed = items.map { item in
                var copy = item
                if !regularFileExists(at: item.fileURL) {
                    copy.status = .missing
                } else if item.status == .pending || item.status == .missing {
                    copy.status = .available
                }
                return copy
            }
            guard !zip(items, refreshed).allSatisfy({ $0.status == $1.status }) else { return false }
            try save(refreshed)
            return true
        }
        if changed {
            notifyChanged()
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
