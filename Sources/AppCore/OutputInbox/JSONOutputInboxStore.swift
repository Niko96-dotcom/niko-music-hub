import Foundation

public struct JSONOutputInboxStore: OutputInboxStore, @unchecked Sendable {
    private let storageURL: URL
    private let fileManager: FileManager

    public init(
        storageURL: URL,
        fileManager: FileManager = .default
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
    }

    public func listItems() throws -> [OutputInboxItem] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return []
        }

        let data = try Data(contentsOf: storageURL)
        return try JSONDecoder().decode([OutputInboxItem].self, from: data)
    }

    public func addItem(_ item: OutputInboxItem) throws {
        var items = try listItems()
        items.append(item)
        try save(items)
    }

    public func updateItem(_ item: OutputInboxItem) throws {
        var items = try listItems()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        try save(items)
    }

    public func refreshAvailability() throws {
        let items = try listItems()
        let refreshed = items.map { item in
            var copy = item
            if !fileManager.fileExists(atPath: item.fileURL.path) {
                copy.status = .missing
            } else if item.status == .pending || item.status == .missing {
                copy.status = .available
            }
            return copy
        }
        guard refreshed != items else { return }
        try save(refreshed)
    }

    private func save(_ items: [OutputInboxItem]) throws {
        let directory = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: storageURL, options: .atomic)
        NotificationCenter.default.post(name: .outputInboxDidChange, object: nil)
    }
}
