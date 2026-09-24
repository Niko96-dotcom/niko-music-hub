import AppCore
import Foundation
import NikoMusicCore
import XCTest

/// Upgraders who configured music folders or Project Vault only from Settings
/// never set archiveOnboardingCompleted, so the new-user sheet must not greet
/// them: it also requires empty music roots and a disabled Vault.
final class HubFirstLaunchSetupPolicyTests: XCTestCase {
    func testDefaultsPresentSetup() {
        XCTAssertTrue(HubFirstLaunchSetupPolicy.shouldPresentSetup(
            store: FixtureSettingsStore(AppSettings()),
            runtimeAllowsAutoSetup: true
        ))
    }

    func testRuntimeVetoHidesSetup() {
        XCTAssertFalse(HubFirstLaunchSetupPolicy.shouldPresentSetup(
            store: FixtureSettingsStore(AppSettings()),
            runtimeAllowsAutoSetup: false
        ))
    }

    func testSetupAssistantShownHidesSetup() {
        var settings = AppSettings()
        settings.setupAssistantShown = true
        XCTAssertFalse(HubFirstLaunchSetupPolicy.shouldPresentSetup(
            store: FixtureSettingsStore(settings),
            runtimeAllowsAutoSetup: true
        ))
    }

    func testArchiveOnboardingCompletedHidesSetup() {
        var settings = AppSettings()
        settings.archiveOnboardingCompleted = true
        XCTAssertFalse(HubFirstLaunchSetupPolicy.shouldPresentSetup(
            store: FixtureSettingsStore(settings),
            runtimeAllowsAutoSetup: true
        ))
    }

    func testConfiguredMusicRootHidesSetup() {
        var settings = AppSettings()
        settings.musicRoots = [
            StoredMusicRoot(role: .scanOnly, url: URL(fileURLWithPath: "/Volumes/Music", isDirectory: true))
        ]
        XCTAssertFalse(HubFirstLaunchSetupPolicy.shouldPresentSetup(
            store: FixtureSettingsStore(settings),
            runtimeAllowsAutoSetup: true
        ))
    }

    func testEnabledVaultHidesSetup() {
        var settings = AppSettings()
        settings.vault.isEnabled = true
        XCTAssertFalse(HubFirstLaunchSetupPolicy.shouldPresentSetup(
            store: FixtureSettingsStore(settings),
            runtimeAllowsAutoSetup: true
        ))
    }

    func testThrowingStoreHidesSetup() {
        XCTAssertFalse(HubFirstLaunchSetupPolicy.shouldPresentSetup(
            store: ThrowingSettingsStore(),
            runtimeAllowsAutoSetup: true
        ))
    }
}

private struct FixtureSettingsStore: SettingsStore {
    let settings: AppSettings

    init(_ settings: AppSettings) {
        self.settings = settings
    }

    func loadSettings() throws -> AppSettings { settings }

    func saveSettings(_ settings: AppSettings) throws {}

    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {}
}

private struct ThrowingSettingsStore: SettingsStore {
    enum LoadFailure: Error {
        case unreadable
    }

    func loadSettings() throws -> AppSettings { throw LoadFailure.unreadable }

    func saveSettings(_ settings: AppSettings) throws {}

    func updateSettings(_ update: @Sendable (inout AppSettings) -> Void) throws {}
}
