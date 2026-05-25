import Foundation

public protocol SettingsStore: Sendable {
    func loadSettings() throws -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws
}
