import AppCore
import Foundation

public struct UserDefaultsBPMHistoryStore: BPMHistoryStore, @unchecked Sendable {
    private let preferences: any PreferenceStore
    private let key: String

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "outsideCubaseHub.bpmHistory"
    ) {
        self.preferences = UserDefaultsPreferenceStore(userDefaults: userDefaults)
        self.key = key
    }

    public init(
        preferences: any PreferenceStore,
        key: String = "outsideCubaseHub.bpmHistory"
    ) {
        self.preferences = preferences
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
        preferences.removeObject(forKey: key)
    }

    private func loadEntries() throws -> [BPMHistoryEntry] {
        guard let data = preferences.data(forKey: key) else {
            return []
        }

        return try JSONDecoder().decode([BPMHistoryEntry].self, from: data)
    }

    private func saveEntries(_ entries: [BPMHistoryEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        preferences.set(data, forKey: key)
    }
}
