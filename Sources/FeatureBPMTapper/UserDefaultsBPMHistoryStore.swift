import Foundation

public struct UserDefaultsBPMHistoryStore: BPMHistoryStore, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key: String

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "outsideCubaseHub.bpmHistory"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    public func listEntries() throws -> [BPMHistoryEntry] {
        try loadEntries()
            .sorted { lhs, rhs in
                lhs.timestamp > rhs.timestamp
            }
    }

    public func addEntry(_ entry: BPMHistoryEntry) throws {
        var entries = try loadEntries()
        entries.append(entry)
        try saveEntries(entries)
    }

    public func clearEntries() throws {
        userDefaults.removeObject(forKey: key)
    }

    private func loadEntries() throws -> [BPMHistoryEntry] {
        guard let data = userDefaults.data(forKey: key) else {
            return []
        }

        return try JSONDecoder().decode([BPMHistoryEntry].self, from: data)
    }

    private func saveEntries(_ entries: [BPMHistoryEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        userDefaults.set(data, forKey: key)
    }
}
