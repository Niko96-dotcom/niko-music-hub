import Combine
import Foundation

public struct UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    public static let defaultOutputFolderDisplayPath = "~/Music/Niko Music Hub/Inbox"
    private static let serializationLock = NSLock()

    private let userDefaults: UserDefaults
    private let key: String
    /// Shared by every copy of this store value, so all consumers of the same
    /// defaults suite see the same change stream.
    private let changeSubject = PassthroughSubject<AppSettings, Never>()

    public var settingsChanges: AnyPublisher<AppSettings, Never> {
        changeSubject.eraseToAnyPublisher()
    }

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
        // Outside the lock: a synchronous subscriber may call back into the store.
        changeSubject.send(settings)
    }

    private func saveSettingsLocked(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: key)
        userDefaults.synchronize()
    }

    public func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        let saved = try Self.serializationLock.withLock {
            var settings = try loadSettingsLocked()
            update(&settings)
            try saveSettingsLocked(settings)
            return settings
        }
        changeSubject.send(saved)
    }

    private static func needsTypedRootMigration(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["musicRoots"] == nil && object["archiveRoots"] != nil
    }
}
