import Foundation

public struct UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    public static let defaultOutputFolderDisplayPath = "~/Music/Niko Music Hub/Inbox"
    private static let serializationLock = NSLock()

    private let userDefaults: UserDefaults
    private let key: String

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "nikoMusicHub.settings"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    public func loadSettings() throws -> AppSettings {
        try Self.serializationLock.withLock {
            try loadSettingsLocked()
        }
    }

    private func loadSettingsLocked() throws -> AppSettings {
        guard let data = userDefaults.data(forKey: key) else {
            return .default
        }

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        if Self.needsTypedRootMigration(data) {
            try saveSettingsLocked(settings)
        }
        return settings
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try Self.serializationLock.withLock {
            try saveSettingsLocked(settings)
        }
    }

    private func saveSettingsLocked(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: key)
        userDefaults.synchronize()
    }

    public func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        try Self.serializationLock.withLock {
            var settings = try loadSettingsLocked()
            update(&settings)
            try saveSettingsLocked(settings)
        }
    }

    private static func needsTypedRootMigration(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["musicRoots"] == nil && object["archiveRoots"] != nil
    }
}
