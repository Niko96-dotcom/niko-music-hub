import Foundation

public struct UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    public static let defaultOutputFolderDisplayPath = "~/Music/Outside Cubase Hub/Inbox"

    private let userDefaults: UserDefaults
    private let key: String

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "outsideCubaseHub.settings"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    public func loadSettings() throws -> AppSettings {
        guard let data = userDefaults.data(forKey: key) else {
            return .default
        }

        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func saveSettings(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: key)
        userDefaults.synchronize()
    }

    public func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {
        var settings = try loadSettings()
        update(&settings)
        try saveSettings(settings)
    }
}
