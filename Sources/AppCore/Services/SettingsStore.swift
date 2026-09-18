import Combine
import Foundation

public protocol SettingsStore: Sendable {
    func loadSettings() throws -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws

    /// Emits the settings that were just persisted, on whichever thread saved
    /// them. Stores that cannot observe changes return a publisher that never
    /// emits; consumers should read `loadSettings()` for the initial value.
    var settingsChanges: AnyPublisher<AppSettings, Never> { get }
}

public extension SettingsStore {
    var settingsChanges: AnyPublisher<AppSettings, Never> {
        Empty(completeImmediately: false).eraseToAnyPublisher()
    }
}
