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
            items.append(item)
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
                if !fileManager.fileExists(atPath: item.fileURL.path) {
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
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .outputInboxDidChange, object: nil)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
