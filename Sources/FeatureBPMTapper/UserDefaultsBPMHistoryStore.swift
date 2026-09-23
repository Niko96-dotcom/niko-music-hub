import AppCore
import Foundation

public enum BPMHistoryStoreError: Error, Equatable {
    case corruptBackupFailed
}

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
        let entries: [BPMHistoryEntry]
        do {
            entries = try loadEntries()
        } catch is DecodingError {
            // B1 recovery: the stored bytes are not a BPM history. Preserve
            // them under the quarantine key, then start fresh so this save
            // succeeds instead of trapping every future Save/Try Again.
            guard let badBytes = preferences.data(forKey: key) else {
                throw BPMHistoryStoreError.corruptBackupFailed
            }
            preferences.set(badBytes, forKey: corruptBackupKey)
            guard preferences.data(forKey: corruptBackupKey) == badBytes else {
                throw BPMHistoryStoreError.corruptBackupFailed
            }
            entries = []
        }
        var fresh = entries
        fresh.append(entry)
        try saveEntries(fresh)
    }

    public func clearEntries() throws {
        guard let live = preferences.data(forKey: key) else {
            return
        }
        // Only quarantine unreadable payloads; valid history clears without
        // touching the backup. The exact malformed bytes are preserved first;
        // if that backup cannot be verified, the live key is left in place.
        let isCorrupt = (try? JSONDecoder().decode([BPMHistoryEntry].self, from: live)) == nil
        if isCorrupt {
            preferences.set(live, forKey: corruptBackupKey)
            guard preferences.data(forKey: corruptBackupKey) == live else {
                throw BPMHistoryStoreError.corruptBackupFailed
            }
        }
        preferences.removeObject(forKey: key)
    }

    /// Quarantine key holding the last unreadable payload seen by `addEntry`.
    public var corruptBackupKey: String {
        key + ".corruptBackup"
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
