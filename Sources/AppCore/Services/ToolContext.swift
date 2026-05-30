import Foundation

public struct ToolContext: Sendable {
    public let registeredToolCount: Int
    public let settingsStore: any SettingsStore
    public let outputInboxStore: any OutputInboxStore
    public let jobRunner: any JobRunning
    public let fileActions: any FileActions
    public let launchAtLogin: any LaunchAtLoginControlling
    public let diagnostics: any Diagnostics

    public init(
        registeredToolCount: Int,
        settingsStore: any SettingsStore,
        outputInboxStore: any OutputInboxStore,
        jobRunner: any JobRunning,
        fileActions: any FileActions,
        launchAtLogin: any LaunchAtLoginControlling = NoopLaunchAtLoginController(),
        diagnostics: any Diagnostics
    ) {
        self.registeredToolCount = registeredToolCount
        self.settingsStore = settingsStore
        self.outputInboxStore = outputInboxStore
        self.jobRunner = jobRunner
        self.fileActions = fileActions
        self.launchAtLogin = launchAtLogin
        self.diagnostics = diagnostics
    }
}
